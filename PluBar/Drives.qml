pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// ---------------------------------------------------------------
// Dyski wpinane (pendrive'y, karty, dyski USB) dla paska.
//
// Stan z `lsblk -J`, a zmiany zgłasza udisks2: `gdbus monitor` na jego
// nazwie wypisuje linię przy każdym podłączeniu, odłączeniu, montowaniu
// i odmontowaniu (także cudzym: udisks obserwuje mountinfo). Po serii
// linii (jedno montowanie to ~8 sygnałów) jeden odczyt lsblk.
//
// Montowanie, odmontowanie i wyłączenie zasilania przez udisksctl, bez
// roota: polkit pozwala na to aktywnej sesji (filesystem-mount,
// power-off-drive, encrypted-unlock: allow_active yes). Montuje do
// /run/media/$USER/<etykieta>, jak menedżery plików.
//
// udisks2 jest uruchamiany przez D-Bus na żądanie (usługa systemd
// wyłączona), więc przed nasłuchem budzimy go `udisksctl status`.
// ---------------------------------------------------------------
Singleton {
    id: root

    // Urządzenia pętli (loop) też jako dyski wpinane — tylko dla sond:
    // `udisksctl loop-setup -f obraz` udaje pendrive'a bez sprzętu.
    property bool includeLoop: false
    // Seria sygnałów udisks → jeden odczyt po tylu ms ciszy.
    property int settleMs: 250
    // Po wyjściu nasłuchu (restart udisks) wznawiamy po tylu ms.
    property int restartMs: 2000
    // Systemy plików, których nie pokazujemy jako woluminów.
    property var hiddenTypes: ["swap", "LVM2_member", "linux_raid_member"]
    // Zerknięcie w wyspie przy wpięciu dysku (przełącznik w ustawieniach).
    property bool announcePlug: Settings.drivesAnnounce

    // [{ path, name, tran, size, released, volumes: [{ path, title, fstype,
    //   size, mount, avail, used, total, locked, crypto }] }]
    // released = odmontowany, ale zasilania nie dało się wyłączyć
    // (czytnik kart): można wyjąć, choć system dalej widzi urządzenie.
    property var disks: []
    readonly property bool present: disks.length > 0
    readonly property int mountedCount: {
        let n = 0;
        for (const d of disks) for (const v of d.volumes) if (v.mount !== "") n++;
        return n;
    }

    // Trwające akcje: { ścieżka: "mount" | "eject" }. Przypisanie nowego
    // obiektu, bo zmiana pola nie przelicza powiązań.
    property var busy: ({})
    readonly property bool working: Object.keys(busy).length > 0
    // Ostatni błąd (krótko, po polsku), czyszczony przy następnej akcji.
    property string error: ""

    property var released: ({})

    // Ścieżki dysków z poprzedniego odczytu: nowa = wpięty. Pierwszy odczyt
    // tylko zapamiętuje (primed), inaczej każdy restart powłoki ogłaszałby
    // wszystko, co już tkwi w porcie.
    property var known: ({})
    property bool primed: false

    // ---------------------------------------------------------------
    // Odczyt
    // ---------------------------------------------------------------

    property bool pending: false
    function refresh() {
        if (lsblk.running) { pending = true; return; }
        lsblk.running = true;
    }

    Process {
        id: lsblk
        command: ["lsblk", "-J", "-b", "-o",
                  "NAME,PATH,TYPE,RM,HOTPLUG,TRAN,SIZE,LABEL,FSTYPE,MOUNTPOINTS,FSAVAIL,FSUSED,FSSIZE,VENDOR,MODEL"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.parse(JSON.parse(text).blockdevices || []);
                } catch (e) {
                    console.warn("Drives: lsblk dał coś, czego nie da się odczytać: " + e);
                }
            }
        }
        onExited: if (root.pending) { root.pending = false; root.refresh(); }
    }

    function clean(s) { return (s || "").replace(/[_\s]+/g, " ").trim(); }

    function volume(node, extra) {
        const mounts = (node.mountpoints || []).filter(m => m);
        return Object.assign({
            path: node.path,
            label: node.label || "",
            fstype: node.fstype || "",
            size: node.size || 0,
            mount: mounts.length > 0 ? mounts[0] : "",
            avail: node.fsavail || 0,
            used: node.fsused || 0,
            total: node.fssize || 0,
            locked: false,
            crypto: ""
        }, extra || {});
    }

    // Woluminy dysku: partycje z systemem plików albo sam dysk bez tablicy
    // partycji (sformatowany w całości). LUKS: odblokowany pokazuje swój
    // system plików (crypto = partycja do zamknięcia przy wysuwaniu),
    // zamknięty sam siebie z locked.
    function volumesOf(disk) {
        const nodes = disk.children && disk.children.length > 0 ? disk.children : [disk];
        const out = [];
        for (const n of nodes) {
            if (n.fstype === "crypto_LUKS") {
                const inner = (n.children || []).find(c => c.fstype);
                out.push(inner ? volume(inner, { crypto: n.path, size: n.size }) : volume(n, { locked: true }));
            } else if (n.fstype && hiddenTypes.indexOf(n.fstype) < 0) {
                out.push(volume(n));
            }
        }
        return out;
    }

    function parse(devices) {
        const out = [];
        const seen = {};
        for (const d of devices) {
            const wanted = d.type === "disk" ? (d.hotplug || d.rm) : (includeLoop && d.type === "loop");
            // Rozmiar 0 = pusty czytnik kart.
            if (!wanted || !(d.size > 0)) continue;

            const vols = volumesOf(d);
            const model = clean([d.vendor, d.model].filter(s => s).join(" "));
            const name = model !== "" ? model
                : vols.length === 1 && vols[0].label !== "" ? vols[0].label
                : d.tran === "mmc" ? "Karta pamięci"
                : d.tran === "usb" ? "Dysk USB" : "Dysk";
            for (let i = 0; i < vols.length; i++)
                vols[i].title = vols[i].label !== "" ? vols[i].label
                              : vols.length === 1 ? name : "Partycja " + (i + 1);

            seen[d.path] = true;
            // Zamontowany znowu (albo nigdy nie zwolniony) = już nie „można wyjąć”.
            const isReleased = !!released[d.path] && vols.every(v => v.mount === "");
            out.push({ path: d.path, name: name, tran: d.tran || "", size: d.size,
                       released: isReleased, volumes: vols });
        }

        // Zwolnione, których już nie ma (wyjęte), wypadają ze zbioru.
        const keep = {};
        for (const p in released) if (seen[p] && out.find(d => d.path === p).released) keep[p] = true;
        released = keep;
        disks = out;

        if (primed && announcePlug)
            for (const d of out) if (!known[d.path]) announce(d);
        known = seen;
        primed = true;
    }

    // Tytuł = nazwa dysku, wartość = rozmiar. Ikony usb / sdCard / harddisk
    // są w IslandIcon wyspy; wyspa bez nich rysuje w tym miejscu „play”.
    function announce(disk) {
        glance(iconFor(disk), disk.name, size(disk.size), "Podłączono · " + size(disk.size));
    }

    // ---------------------------------------------------------------
    // Nasłuch udisks
    // ---------------------------------------------------------------

    Process {
        id: monitor
        command: ["sh", "-c", "udisksctl status >/dev/null 2>&1; exec gdbus monitor --system --dest org.freedesktop.UDisks2"]
        running: true
        stdout: SplitParser { onRead: settle.restart() }
        onExited: restart.start()
    }

    Timer { id: settle; interval: root.settleMs; onTriggered: root.refresh() }
    Timer { id: restart; interval: root.restartMs; onTriggered: monitor.running = true }

    Component.onCompleted: refresh()

    // ---------------------------------------------------------------
    // Akcje
    // ---------------------------------------------------------------

    // Każda akcja to osobny proces: dwa dyski można wysuwać naraz.
    Component {
        id: job
        Process {
            property var finished: null
            stdout: StdioCollector { id: jobOut }
            stderr: StdioCollector { id: jobErr }
            onExited: code => {
                if (finished) finished(code, jobOut.text.trim(), jobErr.text.trim());
                destroy();
            }
        }
    }

    function run(command, finished) {
        const p = job.createObject(root, { command: command, finished: finished });
        p.running = true;
    }

    function mark(path, what) {
        const b = Object.assign({}, busy);
        if (what) b[path] = what; else delete b[path];
        busy = b;
    }

    // Odpowiedź udisksctl → jedno zdanie do panelu.
    function explain(err) {
        if (/NotAuthorized/.test(err)) return "Brak uprawnień (polkit)";
        if (/DeviceBusy|target is busy/i.test(err)) return "Dysk jest w użyciu: zamknij pliki i okna z niego";
        if (/wrong fs type|unknown filesystem|NotSupported/i.test(err)) return "Nieobsługiwany system plików";
        const last = err.split(/\n/).pop().replace(/^.*Error[A-Za-z.]*: /, "");
        return last.length > 90 ? last.slice(0, 90) + "…" : (last || "Nieznany błąd");
    }

    // Klik w wolumin: zamontuj, jeśli trzeba, i otwórz katalog. Ścieżkę
    // podaje findmnt, bo etykieta bywa ze spacją, a „Mounted … at …”
    // zależy od wersji udisksctl. AlreadyMounted (wyścig z kimś innym)
    // to też sukces.
    readonly property string mountScript: `
        out=$(udisksctl mount -b "$1" --no-user-interaction 2>&1) || case $out in
            *AlreadyMounted*) ;;
            *) printf '%s' "$out" >&2; exit 1 ;;
        esac
        findmnt -n -o TARGET --source "$1" | head -n 1`

    function open(vol) {
        if (vol.locked) { unlock(vol.path); return; }
        if (vol.mount !== "") { reveal(vol.mount); return; }
        openPath(vol.path);
    }

    // Też z IPC (po odblokowaniu w terminalu): sama ścieżka urządzenia.
    function openPath(dev) {
        if (busy[dev]) return;
        error = "";
        mark(dev, "mount");
        run(["sh", "-c", mountScript, "plude-drives", dev], (code, out, err) => {
            mark(dev, null);
            refresh();
            if (code !== 0) { error = explain(err); return; }
            if (out !== "") reveal(out);
        });
    }

    function reveal(dir) {
        Quickshell.execDetached(["xdg-open", dir]);
    }

    // Zaszyfrowany: hasło wpisuje się w terminalu (udisksctl pyta sam),
    // a odblokowane urządzenie wraca do nas przez IPC do zamontowania.
    function unlock(dev) {
        const script = 'out=$(udisksctl unlock -b "$1") || { printf "\\nEnter zamyka okno"; read -r _; exit 1; }\n'
            + 'dev=${out##* as }; dev=${dev%.}\n'
            + 'qs -p "$2" ipc call drives open "$dev"';
        Quickshell.execDetached([Settings.terminal, "-e", "sh", "-c", script, "plude-drives", dev, Quickshell.shellDir]);
    }

    // Wysunięcie: odmontuj wszystko z dysku, zamknij LUKS, wyłącz zasilanie.
    // Kod 3 = zasilania nie dało się wyłączyć (czytnik kart, urządzenie
    // pętli), ale wszystko jest już odmontowane i zapisane: można wyjąć.
    readonly property string ejectScript: `
        disk=$1; shift
        for a; do
            dev=\${a#?:}
            case $a in
                u:*) out=$(udisksctl unmount -b "$dev" --no-user-interaction 2>&1) || case $out in
                         *NotMounted*) ;;
                         *) printf '%s' "$out" >&2; exit 1 ;;
                     esac ;;
                l:*) out=$(udisksctl lock -b "$dev" --no-user-interaction 2>&1) || case $out in
                         *NotUnlocked*) ;;
                         *) printf '%s' "$out" >&2; exit 1 ;;
                     esac ;;
            esac
        done
        udisksctl power-off -b "$disk" --no-user-interaction >/dev/null 2>&1 || exit 3`

    function eject(disk) {
        if (busy[disk.path]) return;
        error = "";
        const steps = [];
        for (const v of disk.volumes) {
            if (v.mount !== "") steps.push("u:" + v.path);
            if (v.crypto !== "") steps.push("l:" + v.crypto);
        }
        mark(disk.path, "eject");
        run(["sh", "-c", ejectScript, "plude-drives", disk.path].concat(steps), (code, out, err) => {
            mark(disk.path, null);
            if (code === 0 || code === 3) {
                if (code === 3) {
                    const r = Object.assign({}, released);
                    r[disk.path] = true;
                    released = r;
                }
                glance("check", disk.name, "można wyjąć");
            } else {
                error = explain(err);
                glance("warning", disk.name, "nie wysunięty", error);
            }
            refresh();
        });
    }

    function ejectPath(dev) {
        const d = disks.find(x => x.path === dev || x.volumes.some(v => v.path === dev));
        if (d) eject(d);
    }

    function ejectAll() {
        for (const d of disks) if (!d.released) eject(d);
    }

    function glance(icon, title, value, detail) {
        IslandLink.glance(icon, title, value, "Dyski", detail);
    }

    // ---------------------------------------------------------------
    // Podpisy
    // ---------------------------------------------------------------

    // Jednostki dziesiętne, jak na opakowaniu pendrive'a (32 GB, nie 29,8).
    function size(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let v = bytes || 0;
        let i = 0;
        while (v >= 1000 && i < units.length - 1) { v /= 1000; i++; }
        const n = v >= 100 || i === 0 ? Math.round(v) : Math.round(v * 10) / 10;
        return String(n).replace(".", ",") + " " + units[i];
    }

    function plural(n) {
        const tens = n % 100;
        const ones = n % 10;
        if (n === 1) return "1 dysk";
        if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) return n + " dyski";
        return n + " dysków";
    }

    function iconFor(disk) {
        return disk.tran === "mmc" ? "sdCard" : disk.tran === "usb" ? "usb" : "harddisk";
    }
}
