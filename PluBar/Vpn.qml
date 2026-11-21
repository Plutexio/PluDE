pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// ---------------------------------------------------------------
// VPN dla paska: Tailscale i połączenia VPN / WireGuard z NetworkManagera.
//
// Tailscale: stan z `tailscale status --json`, zmiany zgłasza
// `tailscale debug watch-ipn` (cichy: bez zmian nic nie wypisuje, więc
// odczyt tylko po zdarzeniu). Włączanie `tailscale up` / `down`, węzeł
// wyjściowy `tailscale set --exit-node`. Każdy zapis ustawień tailscaled
// wymaga roota albo operatora: jednorazowo `sudo tailscale set
// --operator=$USER` (opcja w panelu otwiera to w terminalu). Operatora
// czytamy z `tailscale debug prefs` (OperatorUser), żeby podpowiedź stała
// w panelu, zanim ktoś kliknie i dostanie odmowę.
//
// Gołe `tailscale up` nie wymaga powtarzania flag (accept-routes itd.):
// przy zalogowanym profilu tylko ustawia WantRunning.
//
// NetworkManager: `nmcli` (typy vpn i wireguard), zmiany z `nmcli monitor`.
// tailscale0 to w NM zwykłe „tun”, więc się nie dubluje.
//
// Klucz pozycji: "tailscale" albo "nm:<uuid>". Ostatnio włączony trafia
// do settings.json (vpnLast): prawy klik w pasku włącza właśnie jego.
// ---------------------------------------------------------------
Singleton {
    id: root

    // Seria zdarzeń → jeden odczyt po tylu ms ciszy.
    property int settleMs: 300
    // Po wyjściu nasłuchu (tailscaled wstaje, brak NM) wznawiamy po tylu ms.
    // Długo: bez demona nasłuch kończy się od razu i to byłoby odpytywanie.
    property int restartMs: 5000
    // Typy połączeń NetworkManagera, które są VPN-em.
    property var nmTypes: ["vpn", "wireguard"]
    // Polecenie, które daje prawo do `tailscale up/down/set` bez roota.
    readonly property string operatorCommand: "sudo tailscale set --operator=$USER"

    readonly property string user: Quickshell.env("USER") || ""

    // ---------------------------------------------------------------
    // Stan
    // ---------------------------------------------------------------

    // Tailscale: null = brak programu albo demona.
    // { state, ip, writable, exitNode, exitNodes: [{ ip, name, online, active }] }
    property var tailscale: null
    readonly property bool tsRunning: tailscale !== null && tailscale.state === "Running"
    readonly property bool tsNeedsLogin: tailscale !== null
        && (tailscale.state === "NeedsLogin" || tailscale.state === "NeedsMachineAuth")

    // [{ uuid, name, type, state }], state: "activated" | "activating" | ""
    property var nm: []

    // Wspólna lista dla paska i panelu: [{ key, name, on, busy, detail }].
    readonly property var items: {
        const out = [];
        if (tailscale !== null)
            out.push({
                key: "tailscale",
                name: "Tailscale",
                on: tsRunning,
                busy: !!busy.tailscale || tailscale.state === "Starting",
                detail: tsRunning ? (tailscale.exitNode !== "" ? "przez " + tailscale.exitNode : tailscale.ip)
                      : tsNeedsLogin ? "wymaga logowania" : ""
            });
        for (const c of nm)
            out.push({
                key: "nm:" + c.uuid,
                name: c.name,
                on: c.state === "activated",
                busy: !!busy["nm:" + c.uuid] || c.state === "activating",
                detail: c.type === "wireguard" ? "WireGuard" : ""
            });
        return out;
    }
    readonly property bool available: items.length > 0
    readonly property var active: items.filter(i => i.on)
    readonly property bool connected: active.length > 0
    readonly property bool working: items.some(i => i.busy)

    // Trwające akcje: { klucz: true }. Nowy obiekt przy zmianie (zmiana pola
    // nie przelicza powiązań).
    property var busy: ({})
    // Ostatni błąd (jedno zdanie), czyszczony przy następnej akcji.
    property string error: ""
    // Odmowa tailscaled przy ostatniej próbie: panel proponuje operatora.
    property bool denied: false
    readonly property bool needsOperator: tailscale !== null && (!tailscale.writable || denied)

    // ---------------------------------------------------------------
    // Odczyt: Tailscale
    // ---------------------------------------------------------------

    // Oba odczyty w jednym procesie, jako jeden JSON. Pusta odpowiedź (brak
    // programu, demon nie działa) = null. status --json przy zatrzymanym
    // Tailscale też wypisuje stan, nawet jeśli kończy się kodem ≠ 0.
    readonly property string tsScript: `
        ts() {
            out=$(tailscale "$@" 2>/dev/null)
            if [ -n "$out" ]; then printf '%s' "$out"; else printf null; fi
        }
        command -v tailscale >/dev/null || { printf '{"status":null}'; exit; }
        printf '{"status":'; ts status --json
        printf ',"prefs":'; ts debug prefs
        printf '}'`

    property bool tsPending: false
    function refreshTailscale() {
        if (tsRead.running) { tsPending = true; return; }
        tsRead.running = true;
    }

    Process {
        id: tsRead
        command: ["sh", "-c", root.tsScript]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.tailscale = root.parseTailscale(d.status, d.prefs);
                } catch (e) {
                    console.warn("Vpn: tailscale dał coś, czego nie da się odczytać: " + e);
                }
            }
        }
        onExited: if (root.tsPending) { root.tsPending = false; root.refreshTailscale(); }
    }

    function peerName(p) {
        const dns = (p.DNSName || "").split(".")[0];
        return dns || p.HostName || "?";
    }

    function parseTailscale(s, prefs) {
        if (!s || !s.BackendState || s.BackendState === "NoState") return null;
        const nodes = [];
        let exitNode = "";
        for (const id in (s.Peer || {})) {
            const p = s.Peer[id];
            if (!p.ExitNodeOption && !p.ExitNode) continue;
            const node = { ip: (p.TailscaleIPs || [])[0] || "", name: peerName(p),
                           online: !!p.Online, active: !!p.ExitNode };
            nodes.push(node);
            if (node.active) exitNode = node.name;
        }
        nodes.sort((a, b) => a.name.localeCompare(b.name));
        // Root może wszystko; prefs bez odczytu = nie wiemy, nie straszymy.
        const operator = prefs ? (prefs.OperatorUser || "") : user;
        return {
            state: s.BackendState,
            ip: ((s.Self || {}).TailscaleIPs || [])[0] || "",
            writable: user === "root" || operator === user,
            exitNode: exitNode,
            exitNodes: nodes
        };
    }

    // Strumień zdarzeń tailscaled. Pierwsza linia to „Connected.”, potem
    // JSON-y przy każdej zmianie (bez zmian peerów: te przychodzą ciągle).
    Process {
        id: tsWatch
        command: ["sh", "-c", "command -v tailscale >/dev/null || exit 127\n"
                  + "exec tailscale debug watch-ipn --peer-changes=false --peer-patches=false"]
        running: true
        stdout: SplitParser { onRead: tsSettle.restart() }
        // 127 = brak programu: nie ma na co czekać.
        onExited: code => { if (code !== 127) tsRestart.start(); }
    }
    Timer { id: tsSettle; interval: root.settleMs; onTriggered: root.refreshTailscale() }
    Timer { id: tsRestart; interval: root.restartMs; onTriggered: { root.refreshTailscale(); tsWatch.running = true; } }

    // ---------------------------------------------------------------
    // Odczyt: NetworkManager
    // ---------------------------------------------------------------

    property bool nmPending: false
    function refreshNm() {
        if (nmRead.running) { nmPending = true; return; }
        nmRead.running = true;
    }

    Process {
        id: nmRead
        command: ["sh", "-c", "command -v nmcli >/dev/null && exec nmcli -t -f NAME,UUID,TYPE,STATE connection show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const f = root.splitTerse(line);
                    if (f.length < 4 || root.nmTypes.indexOf(f[2]) < 0) continue;
                    out.push({ name: f[0], uuid: f[1], type: f[2], state: f[3] });
                }
                root.nm = out;
            }
        }
        onExited: if (root.nmPending) { root.nmPending = false; root.refreshNm(); }
    }

    // Tryb -t: pola rozdziela „:”, a dwukropek i ukośnik w nazwie są
    // poprzedzone „\”.
    function splitTerse(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) cur += line[++i];
            else if (c === ":") { out.push(cur); cur = ""; }
            else cur += c;
        }
        if (line !== "") out.push(cur);
        return out;
    }

    Process {
        id: nmWatch
        command: ["sh", "-c", "command -v nmcli >/dev/null || exit 127\nexec nmcli monitor"]
        running: true
        stdout: SplitParser { onRead: nmSettle.restart() }
        onExited: code => { if (code !== 127) nmRestart.start(); }
    }
    Timer { id: nmSettle; interval: root.settleMs; onTriggered: root.refreshNm() }
    Timer { id: nmRestart; interval: root.restartMs; onTriggered: { root.refreshNm(); nmWatch.running = true; } }

    function refresh() {
        refreshTailscale();
        refreshNm();
    }

    Component.onCompleted: refresh()

    // ---------------------------------------------------------------
    // Akcje
    // ---------------------------------------------------------------

    Component {
        id: job
        Process {
            property var finished: null
            stdout: StdioCollector { id: jobOut }
            stderr: StdioCollector { id: jobErr }
            onExited: code => {
                if (finished) finished(code, (jobErr.text.trim() || jobOut.text.trim()));
                destroy();
            }
        }
    }

    function run(key, command, finished) {
        const b = Object.assign({}, busy);
        b[key] = true;
        busy = b;
        error = "";
        const p = job.createObject(root, { command: command, finished: (code, out) => {
            const nb = Object.assign({}, busy);
            delete nb[key];
            busy = nb;
            if (key === "tailscale") denied = code !== 0 && /access denied|operator/i.test(out);
            if (code !== 0) error = explain(out);
            finished(code === 0);
            refresh();
        } });
        p.running = true;
    }

    // Odpowiedź tailscale / nmcli → jedno zdanie do panelu.
    function explain(out) {
        if (/access denied|operator/i.test(out)) return "Tailscale odmawia zmian bez roota";
        if (/secrets were required|no agents were available/i.test(out))
            return "VPN wymaga hasła: połącz raz przez nmtui albo nm-connection-editor";
        if (/not authorized|insufficient privileges/i.test(out)) return "Brak uprawnień (polkit)";
        const last = out.split(/\n/).filter(s => s.trim() !== "").pop() || "";
        const msg = last.replace(/^Error: /, "");
        return msg.length > 90 ? msg.slice(0, 90) + "…" : (msg || "Nieznany błąd");
    }

    function find(key) { return items.find(i => i.key === key) || null; }

    // Włącz / wyłącz jedną pozycję. Wynik zgłasza zerknięcie w wyspie:
    // połączenie VPN potrafi iść kilka sekund i nie zawsze patrzymy na pasek.
    function setOn(key, on) {
        const item = find(key);
        if (!item || item.busy) return;
        if (key === "tailscale" && on && tsNeedsLogin) { login(); return; }

        const command = key === "tailscale" ? ["tailscale", on ? "up" : "down"]
            : ["nmcli", "--wait", "30", "connection", on ? "up" : "down", "uuid", key.slice(3)];
        run(key, command, ok => {
            if (ok && on) Settings.set("vpnLast", key);
            if (ok) IslandLink.glance(on ? "lock" : "lockOpen", item.name, on ? "włączony" : "wyłączony", "VPN");
            else IslandLink.glance("warning", item.name, "nie " + (on ? "włączony" : "wyłączony"), "VPN", error);
        });
    }

    function toggle(key) {
        const item = find(key);
        if (item) setOn(key, !item.on);
    }

    // Prawy klik w pasku: wyłącz wszystko, co działa, a przy wyłączonym
    // włącz ostatnio używany (albo pierwszy z listy).
    function quickToggle() {
        if (connected) {
            for (const i of active) setOn(i.key, false);
            return;
        }
        const last = find(Settings.vpnLast);
        const pick = last || items[0];
        if (pick) setOn(pick.key, true);
    }

    // "" = bez węzła wyjściowego (ruch do internetu idzie zwykłą drogą).
    function setExitNode(ip) {
        if (busy.tailscale) return;
        run("tailscale", ["tailscale", "set", "--exit-node=" + ip], ok => {});
    }

    // Logowanie i nadanie operatora wymagają rozmowy (adres w przeglądarce,
    // hasło sudo), więc idą w terminalu, jak hasło do zaszyfrowanego dysku.
    function inTerminal(script) {
        Quickshell.execDetached([Settings.terminal, "-e", "sh", "-c",
            script + '\nprintf "\\nEnter zamyka okno"; read -r _']);
    }

    function login() { inTerminal("tailscale up"); }

    function grantOperator() {
        inTerminal(operatorCommand + ' && echo "Gotowe: PluDE może włączać Tailscale."');
    }
}
