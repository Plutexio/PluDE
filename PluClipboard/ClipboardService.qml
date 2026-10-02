pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common

// ---------------------------------------------------------------
// Historia schowka na wl-clipboard: `wl-paste --watch` zgłasza każdą
// zmianę, clip-store.sh zapisuje treść do pliku, a tutaj siedzi spis
// (~/.local/state/plude/clipboard/index.json) i stan okna.
//
// Treść leży w plikach, nie w spisie: zrzut 4K to kilka MB, a spis
// zapisuje się przy każdym skopiowaniu. Spis ma tylko podgląd tekstu.
// ---------------------------------------------------------------
Singleton {
    id: root

    // Większej treści nie zapamiętujemy (zrzut 4K w PNG to zwykle 2–15 MB).
    property int maxBytes: 32 * 1024 * 1024
    // Tyle tekstu trafia do spisu: z niego jest podpis wiersza i po nim
    // idzie wyszukiwanie. Poniżej 4096, żeby linia z jednego obserwatora
    // szła jednym write() i nie przeplotła się z drugim.
    property int previewBytes: 2400
    // Od wl-copy do wysłania skrótu wklejania: wl-copy musi zdążyć przejąć schowek.
    property int pasteDelayMs: 150
    // Terminale wklejają przez Ctrl+Shift+V. Dopasowanie po fragmencie klasy okna.
    property var terminalClasses: ["ghostty", "kitty", "foot", "alacritty", "wezterm", "konsole", "terminal", "xterm"]

    readonly property string dir: Settings.stateDir + "/clipboard"
    readonly property string storeScript: Quickshell.shellPath("PluClipboard/clip-store.sh")

    // ---------------------------------------------------------------
    // Okno
    // ---------------------------------------------------------------

    property bool open: false
    // Monitor z fokusem w chwili otwarcia: schowek otwiera się tam, gdzie piszesz.
    property var screen: null
    // Okno, które miało fokus przy otwarciu. Do niego idzie wklejenie.
    property string pasteAddress: ""
    property string pasteClass: ""

    readonly property bool pastes: Settings.clipboardPaste && pasteAddress !== ""

    function toggle() { if (open) hide(); else show(); }
    function hide() { open = false; }

    // Powiązania, nie odczyt w show(): Hyprland w Quickshellu zapełnia się
    // dopiero po pierwszym dotknięciu (zmierzone: null przy pierwszym odczycie).
    readonly property var focusedMonitor: Hyprland.focusedMonitor
    readonly property var activeWindow: Hyprland.activeToplevel

    function show() {
        if (open) return;
        screen = focusedMonitor ? (Quickshell.screens.find(s => s.name === focusedMonitor.name) ?? null) : null;

        const win = activeWindow;
        pasteAddress = win && win.address ? win.address : "";
        pasteClass = win && win.wayland ? (win.wayland.appId || "") : "";
        open = true;
    }

    // ---------------------------------------------------------------
    // Spis
    // ---------------------------------------------------------------

    // Wpis: { id, kind: "text" | "image", file, mime, size, info, preview, time, pinned }
    // info: liczba wierszy tekstu albo wymiary obrazu ("1920x1080").
    // Od ostatnio skopiowanego, przypięte wymieszane z resztą (rozdziela je search).
    readonly property var items: store.items
    readonly property var byId: {
        const map = {};
        for (let i = 0; i < items.length; i++) map[items[i].id] = items[i];
        return map;
    }

    // Obserwatorzy ruszają dopiero po wczytaniu spisu. Zdarzenie przed
    // wczytaniem zapisałoby spis z jednym wpisem i skasowało resztę historii.
    property bool ready: false

    FileView {
        path: root.dir + "/index.json"
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) writeAdapter();
            root.ready = true;
        }
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: store
            property var items: []
        }
    }

    onReadyChanged: if (ready) sweep()

    // Dwóch obserwatorów, bo wl-paste bez typu zgłasza tylko tekst (zmierzone:
    // sam obraz w schowku nie budzi polecenia). Który z nich zapisuje wpis,
    // gdy źródło daje i tekst, i obraz, rozstrzyga clip-store.sh.
    component Watcher: Process {
        id: watcher

        required property string kind

        running: root.ready
        command: ["wl-paste", "--type", kind, "--watch", "sh", root.storeScript,
            kind, root.dir, String(root.maxBytes), String(root.previewBytes)]
        stdout: SplitParser {
            onRead: line => root.ingest(line)
        }
        onExited: code => console.warn("Schowek: obserwator (" + watcher.kind + ") zakończył się kodem " + code + ", historia stoi.")
    }

    Watcher { kind: "text" }
    Watcher { kind: "image" }

    // Odwraca zapis z clip-store.sh (\n, \t, \r i \\ jako dwa znaki).
    function unfold(text) {
        return text.replace(/\\(.)/g, (m, c) => c === "n" ? "\n" : c === "t" ? "\t" : c === "r" ? "\r" : c);
    }

    function ingest(line) {
        const f = line.split("\t");
        if (f.length < 7) return;
        const id = f[1];

        // To, co już stoi na górze: obserwator po starcie zgłasza bieżącą
        // treść schowka, a przeładowanie powłoki nie jest nowym skopiowaniem.
        if (items.length > 0 && items[0].id === id) return;

        const old = byId[id];
        const list = items.filter(e => e.id !== id);
        list.unshift({
            id: id,
            kind: f[0],
            file: f[2],
            size: parseInt(f[3]) || 0,
            info: f[4],
            mime: f[5],
            preview: f[0] === "text" ? unfold(f[6]) : "",
            time: Date.now(),
            pinned: old ? old.pinned : false
        });
        commit(list);
    }

    // Zapis listy z przycięciem do limitu. Przypięte nie wliczają się i nie wypadają.
    function commit(list) {
        const kept = [], dropped = [];
        let free = 0;
        for (let i = 0; i < list.length; i++) {
            if (list[i].pinned || free++ < Settings.clipboardMax) kept.push(list[i]);
            else dropped.push(list[i]);
        }
        store.items = kept;
        removeFiles(dropped);
    }

    function path(e) { return dir + "/" + e.file; }

    function removeFiles(list) {
        if (list.length === 0) return;
        Quickshell.execDetached(["rm", "-f", "--"].concat(list.map(path)));
    }

    // Pliki, których nie ma w spisie (wpis wypadł, a powłoka padła przed
    // skasowaniem pliku). Świeżych nie ruszamy: mogą należeć do wpisu, który
    // obserwator właśnie zgłasza.
    function sweep() {
        const script = "cd \"$1\" 2>/dev/null || exit 0; shift; "
            + "find . -maxdepth 1 -type f -mmin +1 ! -name index.json | while read -r f; do "
            + "keep=0; for k in \"$@\"; do [ \"./$k\" = \"$f\" ] && keep=1 && break; done; "
            + "[ $keep = 1 ] || rm -f -- \"$f\"; done";
        Quickshell.execDetached(["sh", "-c", script, "plude-clip-sweep", dir].concat(items.map(e => e.file)));
    }

    Connections {
        target: Settings
        function onClipboardMaxChanged() { if (root.ready) root.commit(root.items); }
    }

    // ---------------------------------------------------------------
    // Akcje
    // ---------------------------------------------------------------

    // Wpis z powrotem do schowka i (jeśli włączone) od razu do okna, z którego
    // otwarto schowek. Obserwator zobaczy tę zmianę i przeniesie wpis na górę.
    function choose(id) {
        const e = byId[id];
        if (!e) return;

        let paste = "";
        if (pastes) {
            const cls = pasteClass.toLowerCase();
            const terminal = cls !== "" && (cls === Settings.terminal.toLowerCase()
                || terminalClasses.some(t => cls.indexOf(t) >= 0));
            paste = "hl.dsp.send_shortcut({ mods = \"" + (terminal ? "CTRL SHIFT" : "CTRL")
                + "\", key = \"V\", window = \"address:0x" + pasteAddress.replace(/^0x/, "") + "\" })";
        }
        hide();

        // Tekst bez --type: wl-copy sam wystawia wtedy wszystkie odmiany
        // text/plain (UTF8_STRING, STRING…), których chcą starsze aplikacje.
        const script = "if [ \"$1\" = text/plain ]; then wl-copy < \"$2\"; else wl-copy --type \"$1\" < \"$2\"; fi"
            + " && [ -n \"$3\" ] && sleep \"$4\" && hyprctl dispatch \"$3\"";
        Quickshell.execDetached(["sh", "-c", script, "plude-clip", e.mime, path(e), paste, String(pasteDelayMs / 1000)]);
    }

    function togglePin(id) {
        commit(items.map(e => e.id === id ? Object.assign({}, e, { pinned: !e.pinned }) : e));
    }

    function remove(id) {
        const e = byId[id];
        if (!e) return;
        store.items = items.filter(x => x.id !== id);
        removeFiles([e]);
    }

    // Czyści historię. Przypięte zostają: po to się je przypina.
    function clear() {
        removeFiles(items.filter(e => !e.pinned));
        store.items = items.filter(e => e.pinned);
    }

    readonly property int unpinnedCount: items.filter(e => !e.pinned).length

    // ---------------------------------------------------------------
    // Opis wpisu i wyszukiwanie
    // ---------------------------------------------------------------

    // "link", "color", "text" albo "image": od tego zależy ikona wiersza.
    function flavor(e) {
        if (e.kind === "image") return "image";
        const t = e.preview.trim();
        if (/^(https?|ftp):\/\/\S+$/i.test(t)) return "link";
        if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t)) return "color";
        return "text";
    }

    function title(e) {
        if (e.kind === "image") return "Obraz" + (e.info !== "" ? " " + e.info.replace("x", " × ") : "");
        return e.preview.replace(/\s+/g, " ").trim();
    }

    function plural(n, one, few, many) {
        const d = n % 10, h = n % 100;
        if (n === 1) return one;
        return d >= 2 && d <= 4 && (h < 12 || h > 14) ? few : many;
    }

    function bytes(n) {
        if (n < 1024) return n + " B";
        if (n < 1024 * 1024) return Math.round(n / 1024) + " kB";
        return (n / 1024 / 1024).toFixed(1).replace(".", ",") + " MB";
    }

    function detail(e) {
        if (e.kind === "image") return e.mime.replace("image/", "").toUpperCase() + " · " + bytes(e.size);
        const kind = flavor(e);
        if (kind === "link") return "Odnośnik";
        if (kind === "color") return "Kolor";
        const lines = parseInt(e.info) || 1;
        return lines > 1 ? lines + " " + plural(lines, "wiersz", "wiersze", "wierszy") + " · " + bytes(e.size)
                         : "Tekst";
    }

    function ago(time, now) {
        const min = Math.floor((now - time) / 60000);
        if (min < 1) return "teraz";
        if (min < 60) return min + " min";
        const h = Math.floor(min / 60);
        if (h < 24) return h + " godz.";
        const days = Math.floor(h / 24);
        if (days === 1) return "wczoraj";
        if (days < 7) return days + " dni";
        return Qt.formatDate(new Date(time), "d.MM.yyyy");
    }

    // Przypięte na górze, w obu grupach od najnowszego. Szukamy w podglądzie
    // tekstu, obraz znajduje się po słowie „obraz”, formacie i wymiarach.
    function search(query) {
        const q = (query || "").trim().toLowerCase();
        const hit = e => q === ""
            || (e.kind === "image" ? ("obraz image " + e.mime + " " + e.info) : e.preview).toLowerCase().indexOf(q) >= 0;
        const list = items.filter(hit);
        return list.filter(e => e.pinned).concat(list.filter(e => !e.pinned));
    }
}
