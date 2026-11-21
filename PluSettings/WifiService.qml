pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Common

// ---------------------------------------------------------------
// Wi-Fi dla strony ustawień: stan, łączenie i edycja zapisanych sieci.
//
// Quickshell.Networking nie zna pasma, kanału, adresów ani ustawień
// profilu, a connectWithSettings() chce typu, którego nie da się utworzyć
// z QML (wyspa, NetworkService). Dlatego:
//   - stan: nm-wifi.py watch (libnm), jeden proces na czas otwartej
//     strony, JSON po każdej zmianie. Odpytywanie kosztowałoby ~0,4 s
//     procesora na odczyt (sam import gi, zmierzone);
//   - łączenie i hasła: nm-wifi.py z prośbą na stdin (hasło w argv
//     widziałby każdy proces użytkownika);
//   - reszta ustawień profilu: nmcli connection modify, które samo
//     parsuje adresy i sprawdza wartości.
// Włącznik Wi-Fi idzie przez Networking, jak w pasku.
//
// Singleton powstaje przy pierwszym dotknięciu; nasłuch chodzi tylko,
// gdy strona go trzyma (`watchers`).
// ---------------------------------------------------------------
Singleton {
    id: root

    // Po wyjściu nasłuchu (restart NetworkManagera) wznawiamy po tylu ms.
    property int restartMs: 3000
    // Tyle po zleceniu skanowania pokazujemy kręcące się „Odśwież”:
    // wyniki dochodzą przez nasłuch, a zlecenie wraca od razu.
    property int scanShowMs: 4000

    readonly property string helper: Quickshell.shellPath("PluSettings/nm-wifi.py")

    // ---------------------------------------------------------------
    // Stan (z nm-wifi.py, opis pól w state_of())
    // ---------------------------------------------------------------

    property bool ready: false
    property bool enabled: Networking.wifiEnabled
    property bool hardwareEnabled: Networking.wifiHardwareEnabled
    // NMConnectivityState: 0 nieznana, 1 brak, 2 portal, 3 ograniczona, 4 pełna
    property int connectivity: 0
    property var device: null
    property var active: null
    property var aps: []
    property var profiles: []

    readonly property bool available: device !== null
    readonly property string iface: device ? device.iface : ""

    // Stan nasłuchu trzymają strony: ++ przy utworzeniu, -- przy zniszczeniu.
    property int watchers: 0
    readonly property bool watching: watchers > 0

    // ---- sieci w zasięgu ----

    // Jedna pozycja na nazwę: najsilniejszy punkt dostępowy, do tego
    // wszystkie pasma, w których sieć jest. Ukryte (bez nazwy) odpadają,
    // do nich jest formularz „Inna sieć”.
    // [{ ssid, signal, band, bands, channel, security, securityKey, active,
    //    bssid, profile (zapisany profil albo null) }]
    readonly property var networks: {
        const by = {};
        aps.forEach(ap => {
            if (ap.ssid === "") return;
            const n = by[ap.ssid];
            if (!n) {
                by[ap.ssid] = Object.assign({ bands: [ap.band] }, ap);
                return;
            }
            if (n.bands.indexOf(ap.band) < 0) n.bands.push(ap.band);
            // Bieżący punkt wygrywa: pokazujemy pasmo, na którym jesteśmy.
            if (ap.active || (!n.active && ap.signal > n.signal))
                Object.assign(n, ap, { bands: n.bands, active: n.active || ap.active });
        });
        return Object.keys(by).map(k => {
            const n = by[k];
            n.bands.sort();
            n.profile = profileFor(n.ssid);
            return n;
        }).sort((a, b) => {
            if (a.active !== b.active) return a.active ? -1 : 1;
            if ((a.profile !== null) !== (b.profile !== null)) return a.profile !== null ? -1 : 1;
            return b.signal - a.signal;
        });
    }

    // Zapisane sieci klienckie (bez hotspotów), ostatnio używane na górze.
    readonly property var savedProfiles: profiles.filter(p => p.mode === "infrastructure")
        .sort((a, b) => b.timestamp - a.timestamp || a.name.localeCompare(b.name))

    // Profil dla nazwy sieci: aktywny, a z kilku o tej samej nazwie
    // ostatnio używany (tak wybiera też NetworkManager przy autołączeniu).
    function profileFor(ssid) {
        let best = null;
        profiles.forEach(p => {
            if (p.ssid !== ssid || p.mode !== "infrastructure") return;
            if (active && p.uuid === active.uuid) { best = p; return; }
            if (best && active && best.uuid === active.uuid) return;
            if (!best || p.timestamp > best.timestamp) best = p;
        });
        return best;
    }

    function profile(uuid) {
        for (let i = 0; i < profiles.length; i++) if (profiles[i].uuid === uuid) return profiles[i];
        return null;
    }

    // Bieżące połączenie z danymi punktu dostępowego (pasmo, sygnał).
    // ACTIVATED = 2; w trakcie łączenia `active` już jest, ale bez adresów.
    readonly property var current: {
        if (!active) return null;
        const ap = aps.find(a => a.active) || null;
        return Object.assign({}, active, {
            connected: active.state === 2,
            signal: ap ? ap.signal : 0,
            band: ap ? ap.band : "",
            channel: ap ? ap.channel : 0,
            security: ap ? ap.security : "",
            bitrate: device ? device.bitrate : 0
        });
    }

    // ---------------------------------------------------------------
    // Nazwy
    // ---------------------------------------------------------------

    function bandLabel(b) { return b === "2.4" ? "2,4 GHz" : b + " GHz"; }

    function bandsLabel(list) { return list.map(bandLabel).join(" + "); }

    function rateLabel(kbit) { return kbit > 0 ? Math.round(kbit / 1000) + " Mb/s" : ""; }

    // Te same progi co w pasku (Connectivity.netIcon).
    function signalIcon(pct) { return pct >= 67 ? "wifi" : pct >= 34 ? "wifi2" : "wifi1"; }

    function needsSecret(key) { return key === "wpa-psk" || key === "sae" || key === "wep"; }

    // key-mgmt profilu → nazwa.
    function profileSecurity(p) {
        switch (p.security) {
        case "wpa-psk": return "WPA/WPA2 Personal";
        case "sae": return "WPA3 Personal";
        case "wpa-eap": return "802.1X" + (p.eap !== "" ? " (" + p.eap.toUpperCase() + ")" : "");
        case "none": return "WEP";
        case "owe": return "Otwarta, szyfrowana (OWE)";
        default: return "Otwarta";
        }
    }

    function hasSecret(p) {
        return p !== null && (p.security === "wpa-psk" || p.security === "sae"
            || p.security === "none" || p.security === "wpa-eap");
    }

    // Znacznik czasu NetworkManagera (s) → „3 dni temu”.
    function ago(ts) {
        if (!ts) return "nigdy";
        const now = new Date();
        const then = new Date(ts * 1000);
        const day = d => Math.floor((d.getTime() - d.getTimezoneOffset() * 60000) / 86400000);
        const days = day(now) - day(then);
        if (days <= 0) return "dzisiaj";
        if (days === 1) return "wczoraj";
        if (days < 7) return days + " dni temu";
        if (days < 30) return Math.floor(days / 7) === 1 ? "tydzień temu" : Math.floor(days / 7) + " tyg. temu";
        return then.toLocaleDateString(Qt.locale("pl_PL"), "d MMM yyyy");
    }

    readonly property string connectivityLabel: connectivity === 4 ? "Internet działa"
        : connectivity === 2 ? "Sieć wymaga zalogowania (portal)"
        : connectivity === 3 ? "Połączono, ale bez internetu"
        : connectivity === 1 ? "Brak sieci" : "Nie sprawdzono"

    // ---------------------------------------------------------------
    // Nasłuch
    // ---------------------------------------------------------------

    function ingest(line) {
        let d;
        try { d = JSON.parse(line); } catch (e) { return; }
        if (!d.ok) {
            console.warn("Wi-Fi: " + (d.error || "pomocnik nie podał stanu"));
            return;
        }
        // Tylko to, co się zmieniło: stan przychodzi co kilka sekund (siła
        // sygnału), a każde przypisanie przelicza wszystkie powiązania,
        // także podstrony sieci, w której ktoś właśnie coś wpisuje.
        connectivity = d.connectivity;
        ["device", "active", "aps", "profiles"].forEach(k => {
            const json = JSON.stringify(d[k]);
            if (json === seen[k]) return;
            seen[k] = json;
            root[k] = d[k];
        });
        ready = true;
    }

    property var seen: ({})

    Process {
        id: watcher
        running: root.watching
        command: ["python3", root.helper, "watch"]
        stdout: SplitParser { onRead: line => root.ingest(line) }
        stderr: SplitParser { onRead: line => { if (line.trim() !== "") console.warn("[wifi] " + line); } }
        // Kod 2 = brak libnm albo NetworkManagera. Wznawiamy mimo to:
        // NetworkManager mógł się właśnie restartować.
        onExited: if (root.watching) restart.start()
    }
    Timer { id: restart; interval: root.restartMs; onTriggered: watcher.running = root.watching }

    // Skanowanie w tle tylko przy otwartej stronie: każde skanowanie
    // zrywa na chwilę transmisję karty (jak NetworkService wyspy).
    readonly property var qsDevice: {
        const all = Networking.devices.values;
        for (let i = 0; i < all.length; i++) if (all[i].type === DeviceType.Wifi) return all[i];
        return null;
    }
    onWatchingChanged: if (qsDevice) qsDevice.scannerEnabled = watching
    onQsDeviceChanged: if (qsDevice) qsDevice.scannerEnabled = watching

    // ---------------------------------------------------------------
    // Akcje
    // ---------------------------------------------------------------

    // Ostatni błąd poza łączeniem (zapis profilu, zapomnienie), czyszczony
    // przy następnej akcji.
    property string error: ""
    // Uuid profilu, który właśnie się zapisuje: strona wyszarza wiersze.
    property string saving: ""

    // Łączenie: nazwa sieci albo "" i wynik ostatniej próby.
    property string connecting: ""
    property string connectError: ""
    property string connectErrorFor: ""
    readonly property bool busy: connecting !== ""

    property bool scanning: false

    function setEnabled(on) { Networking.wifiEnabled = on; }

    function scan() {
        scanning = true;
        scanTimer.restart();
        runner.enqueue({ command: ["python3", root.helper], input: JSON.stringify({ action: "scan" }) });
    }
    Timer { id: scanTimer; interval: root.scanShowMs; onTriggered: root.scanning = false }

    function startConnect(ssid, request) {
        if (busy) return;
        connecting = ssid;
        connectError = "";
        connectErrorFor = "";
        connector.enqueue({
            command: ["python3", root.helper],
            input: JSON.stringify(request),
            done: (code, out) => {
                const r = root.lastJson(out);
                root.connecting = "";
                if (!r || !r.ok) {
                    root.connectError = r ? r.error : "Pomocnik nie odpowiedział.";
                    root.connectErrorFor = ssid;
                }
            }
        });
    }

    // Sieć z zapisanym profilem: bez pytania o hasło.
    function connectSaved(p, bssid) {
        startConnect(p.ssid, { action: "up", uuid: p.uuid, bssid: bssid || "" });
    }

    // Nowa sieć. params: { ssid, security, psk, hidden, autoconnect, bssid,
    // eap, identity, password, phase2 } — jak „add” w nm-wifi.py.
    function connectNew(params) {
        startConnect(params.ssid, Object.assign({ action: "add" }, params));
    }

    // Rozłączenie urządzenia, nie profilu: NetworkManager nie łączy się
    // wtedy sam z inną zapisaną siecią, dopóki ktoś o to nie poprosi.
    function disconnect() {
        if (iface === "") return;
        nmcli(["device", "disconnect", iface], "");
    }

    function forget(uuid) { nmcli(["connection", "delete", uuid], uuid); }

    // Zmiana profilu: pary klucz–wartość dla nmcli connection modify.
    // Aktywny profil dostaje je od razu przez reapply, a co się tak nie da
    // (adres MAC), przez ponowne połączenie z tą samą siecią.
    function modify(uuid, pairs) {
        error = "";
        saving = uuid;
        const live = active !== null && active.uuid === uuid ? "1" : "0";
        const script = 'u=$1; iface=$2; live=$3; shift 3\n'
            + 'nmcli connection modify "$u" "$@" 2>&1 || exit 1\n'
            + '[ "$live" = 1 ] || exit 0\n'
            + 'nmcli device reapply "$iface" >/dev/null 2>&1 || nmcli -w 30 connection up "$u" 2>&1 >/dev/null\n';
        runner.enqueue({
            command: ["sh", "-c", script, "plude-wifi", uuid, iface, live].concat(pairs.map(String)),
            done: (code, out) => {
                if (root.saving === uuid) root.saving = "";
                if (code !== 0) root.error = root.nmcliError(out);
            }
        });
    }

    // Hasło zapisanego profilu (do pokazania i kodu QR): done(tekst | null).
    function readSecret(uuid, done) {
        runner.enqueue({
            command: ["python3", root.helper],
            input: JSON.stringify({ action: "secret", uuid: uuid }),
            done: (code, out) => {
                const r = root.lastJson(out);
                if (!r || !r.ok) root.error = r ? r.error : "Nie udało się odczytać hasła.";
                done(r && r.ok ? r.secret : null);
            }
        });
    }

    function setSecret(uuid, secret, done) {
        error = "";
        saving = uuid;
        runner.enqueue({
            command: ["python3", root.helper],
            input: JSON.stringify({ action: "setSecret", uuid: uuid, secret: secret }),
            done: (code, out) => {
                if (root.saving === uuid) root.saving = "";
                const r = root.lastJson(out);
                if (!r || !r.ok) root.error = r ? r.error : "Nie udało się zapisać hasła.";
                if (done) done(r !== null && r.ok);
            }
        });
    }

    // Kod QR do udostępnienia sieci (format WIFI: z Androida i iOS).
    // Tekst idzie do qrencode przez stdin: w argv byłoby hasło.
    function qrSvg(p, secret, done) {
        const esc = s => String(s).replace(/([\\;,:"])/g, "\\$1");
        const type = p.security === "none" ? "WEP" : secret === "" ? "nopass" : "WPA";
        const payload = "WIFI:T:" + type + ";S:" + esc(p.ssid) + ";"
            + (secret !== "" ? "P:" + esc(secret) + ";" : "") + (p.hidden ? "H:true;" : "") + ";";
        runner.enqueue({
            command: ["qrencode", "-t", "SVG", "-o", "-", "-m", "2", "--svg-path"],
            input: payload,
            done: (code, out) => done(code === 0 ? "data:image/svg+xml;charset=utf-8," + encodeURIComponent(out) : "")
        });
    }

    function nmcli(args, savingUuid) {
        error = "";
        if (savingUuid) saving = savingUuid;
        runner.enqueue({
            command: ["sh", "-c", 'nmcli "$@" 2>&1', "plude-wifi"].concat(args),
            done: (code, out) => {
                if (savingUuid && root.saving === savingUuid) root.saving = "";
                if (code !== 0) root.error = root.nmcliError(out);
            }
        });
    }

    // „Error: failed to modify ipv4.addresses: …” → samo sedno.
    function nmcliError(out) {
        const lines = out.trim().split("\n").filter(l => l !== "");
        const last = lines.length > 0 ? lines[lines.length - 1] : "";
        return last.replace(/^Error:\s*/, "") || "NetworkManager odrzucił zmianę.";
    }

    function lastJson(out) {
        const lines = out.trim().split("\n");
        for (let i = lines.length - 1; i >= 0; i--) {
            try { return JSON.parse(lines[i]); } catch (e) {}
        }
        return null;
    }

    // Kolejka procesów: jedno polecenie naraz, odpowiedź po wyjściu I końcu
    // stdout (kolejność tych sygnałów nie jest gwarantowana). Prośba idzie
    // na stdin, który potem zamykamy — pomocnik czyta do końca pliku.
    component Runner: Process {
        id: proc

        property var queue: []
        property var job: null
        property int steps: 0
        property int code: 0

        function enqueue(j) {
            queue = queue.concat([j]);
            if (job === null) next();
        }

        function next() {
            if (queue.length === 0) return;
            job = queue[0];
            queue = queue.slice(1);
            stdinEnabled = job.input !== undefined;
            command = job.command;
            running = true;
        }

        function step() {
            if (++steps < 2) return;
            const j = job;
            job = null;
            if (j && j.done) j.done(code, collector.text);
            next();
        }

        onStarted: {
            steps = 0;
            if (job && job.input !== undefined) {
                write(job.input);
                stdinEnabled = false;
            }
        }
        onExited: c => { code = c; step(); }
        stdout: StdioCollector { id: collector; onStreamFinished: proc.step() }
    }

    Runner { id: runner }
    // Łączenie osobno: czeka do 40 s, a zapis ustawień nie może stać za nim.
    Runner { id: connector }
}
