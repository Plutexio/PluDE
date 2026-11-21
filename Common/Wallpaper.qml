pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ---------------------------------------------------------------
// Tapeta i paleta z niej.
//
// Tapetą rządzi skwd-wall (demon skwd-walld, picker skwd-wall-v2). My tylko
// słuchamy jego zdarzeń (`skwd-helm watch`, linia JSON na zdarzenie)
// i przy `skwd.wall.applied` liczymy kolory sami, matugenem z własnymi
// ustawieniami. Kolorów skwd-wall nie bierzemy: jego domyślny backend
// (iris) dał zieleń dla turkusowej tapety, matugen trafił w turkus.
//
// Wynik (same gotowe tokeny, nie cały schemat) idzie do palette.json
// w katalogu ustawień. Z niego czyta Theme, a przy starcie powłoki nie
// trzeba nic liczyć, dopóki tapeta jest ta sama (`source`).
//
// Bez skwd-wall albo matugena zostaje ostatni palette.json, a bez niego
// stałe kolory z Theme (dawny niebieski).
// ---------------------------------------------------------------
Singleton {
    id: root

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    // scheme-vibrant: akcenty nasycone. Domyślny tonal-spot daje wyblakłe.
    property string scheme: "scheme-vibrant"
    // Kiedy obraz ma kilka kandydatów na kolor źródłowy, matugen bez tego
    // pyta w terminalu i kończy się błędem.
    property string prefer: "saturation"

    // Tony palet Material (0–100, jasność). Akcent 70: pełny i jasny na
    // ciemnym tle; tekst na nim ciemny (accentInk).
    property int accentTone: 70
    property int accentBrightTone: 80
    property int accentDeepTone: 30
    property int accentInkTone: 10
    // Obrót odcienia drugiego akcentu (ułamek koła, 0.1 = 36°).
    property real hueStep: 0.1
    // Do tego odcienia (ułamek koła, 0.28 ≈ 100°) obrót idzie wstecz.
    property real warmUntil: 0.28

    // Seria linii z watch (jedna zmiana tapety to kilka zdarzeń) → jeden odczyt.
    property int settleMs: 150
    // Watch padł (restart demona): ponowna próba po tylu ms.
    property int retryMs: 5000

    // Podbij przy zmianie sposobu liczenia tokenów: stary palette.json
    // przelicza się wtedy przy starcie, nawet dla tej samej tapety.
    readonly property int format: 2

    readonly property string file: Settings.configDir + "/palette.json"
    readonly property string thumbDir: Quickshell.env("HOME") + "/.cache/skwd-wall-v2/thumbs"

    // ---------------------------------------------------------------
    // Stan
    // ---------------------------------------------------------------

    // Gotowe tokeny ({ accent: "#…", … }) albo {} bez palety.
    readonly property var colors: priv.data.colors || ({})
    readonly property bool active: Object.keys(colors).length > 0
    // Obraz, z którego policzono paletę.
    readonly property string source: priv.data.source || ""
    readonly property string wallpaper: priv.wallpaper

    function color(name, fallback) {
        return colors[name] !== undefined ? colors[name] : fallback;
    }

    // Ponowne liczenie bieżącej tapety (np. po zmianie schematu).
    function refresh() { priv.force = true; current.running = true; }

    // Paleta (albo stałe kolory Theme bez niej) do Hyprlanda, hyprlocka
    // i wlogouta. Theme.hex w funkcji, nie w powiązaniu: Theme sam czyta
    // stąd kolory, więc powiązanie w drugą stronę zrobiłoby pętlę.
    function exportPalette() {
        const base = {
            surface: Theme.baseSurface, surfaceRaised: Theme.baseSurfaceRaised,
            text: Theme.baseText, textDim: Theme.baseTextDim, textFaint: Theme.baseTextFaint,
            accent: Theme.baseAccent, accent2: Theme.baseAccent2,
            warning: Theme.warning, danger: Theme.danger
        };
        const c = {};
        for (const k in base) c[k] = colors[k] !== undefined ? colors[k] : "#" + Theme.hex(base[k]);
        exporter.write(c);
    }

    PaletteExport { id: exporter }

    QtObject {
        id: priv
        property var data: ({})
        property string wallpaper: ""
        property string pending: ""     // obraz czekający na matugena
        property bool force: false
        property bool loaded: false
    }

    // ---------------------------------------------------------------
    // Plik palety
    // ---------------------------------------------------------------

    FileView {
        id: store
        path: root.file
        watchChanges: true
        printErrors: false   // brak pliku przy pierwszym starcie to nie błąd

        onFileChanged: reload()
        onLoaded: {
            try {
                priv.data = JSON.parse(text());
            } catch (e) {
                // W trakcie zapisu albo uszkodzony: zostaje poprzednia paleta.
            }
            root.firstLoad();
        }
        onLoadFailed: root.firstLoad()
    }

    function firstLoad() {
        if (priv.loaded) return;
        priv.loaded = true;
        exportPalette();
    }

    // ---------------------------------------------------------------
    // skwd-wall
    // ---------------------------------------------------------------

    // Która tapeta jest „nasza”: ta z monitora docka. Tapeta na wszystkich
    // monitorach (output "*") też.
    function ownOutput(output) {
        return output === "*" || output === "" || !Settings.screen || output === Settings.screen.name;
    }

    // Obraz do liczenia: plik statycznej tapety, a dla wideo i scen
    // Wallpaper Engine miniatura z cache skwd-wall (ta sama nazwa, .webp).
    function imageFor(path, type) {
        if (type === "static" || type === undefined) return path;
        const base = path.replace(/^.*\//, "").replace(/\.[^.]*$/, "");
        return thumbDir + "/" + base + ".webp";
    }

    function consider(path, type) {
        if (!path) return;
        priv.wallpaper = path;
        const image = imageFor(path, type);
        if (!priv.force && image === root.source && priv.data.format === format) return;
        priv.force = false;
        priv.pending = image;
        if (!matugen.running) matugen.run(image);
    }

    // Bieżąca tapeta przy starcie (i po restarcie demona): zdarzenia z
    // watch przychodzą tylko przy zmianie.
    Process {
        id: current
        command: ["skwd-helm", "current", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const outs = JSON.parse(text).outputs || [];
                    const own = outs.find(o => root.ownOutput(o.name)) || outs[0];
                    if (own) root.consider(own.path || own.current, own.type);
                } catch (e) {
                    // Demon nie działa: skwd-helm wypisuje błąd, nie JSON.
                }
            }
        }
    }

    Process {
        id: watch
        command: ["skwd-helm", "watch"]
        running: priv.loaded
        stdout: SplitParser {
            onRead: line => {
                let ev;
                try { ev = JSON.parse(line); } catch (e) { return; }
                if (ev.event !== "skwd.wall.applied" || !ev.data) return;
                if (!root.ownOutput(ev.data.output)) return;
                settle.path = ev.data.path;
                settle.type = ev.data.type;
                settle.restart();
            }
        }
        onRunningChanged: if (running) current.running = true
        // 127: brak skwd-helm, nie ma czego wznawiać.
        onExited: code => { if (code !== 127) retry.restart(); }
    }

    Timer {
        id: settle
        property string path: ""
        property string type: ""
        interval: root.settleMs
        onTriggered: root.consider(path, type)
    }

    Timer {
        id: retry
        interval: root.retryMs
        onTriggered: watch.running = true
    }

    // ---------------------------------------------------------------
    // matugen
    // ---------------------------------------------------------------

    // Dwa przebiegi: obraz → schemat, potem `matugen color` z kolorem
    // źródłowym obróconym o hueStep → drugi akcent. Drugi akcent to nie
    // tertiary matugena: w scheme-vibrant bywa prawie szary (turkusowa
    // tapeta: #9dabce), a gradient do szarości wygląda martwo. Obrót w HSL
    // też odpadł: nie trzyma jasności (pomarańcz → jaskrawa limonka,
    // turkus → ciemny granat), a ton z palety HCT trzyma.
    Process {
        id: matugen
        property string image: ""
        property var scheme: null      // wynik pierwszego przebiegu

        function run(img) {
            image = img;
            scheme = null;
            priv.pending = "";
            command = ["matugen", "image", img, "--dry-run", "-q", "-j", "hex",
                       "-t", root.scheme, "-m", "dark", "--prefer", root.prefer];
            running = true;
        }

        function runSecond(m) {
            scheme = m;
            const src = Qt.color(m.colors.source_color.dark.color);
            // Ciepłe (czerwień–żółć) obracamy wstecz, ku różowi; reszta naprzód,
            // ku fioletowi. Naprzód od pomarańczu wychodziła oliwka (#abb242).
            const step = src.hslHue >= 0 && src.hslHue < root.warmUntil ? -root.hueStep : root.hueStep;
            const turned = src.hslHue < 0 ? src
                : Qt.hsla((src.hslHue + step + 1) % 1, src.hslSaturation, src.hslLightness, 1);
            command = ["matugen", "color", "hex", String(turned).replace("#", ""), "--dry-run", "-q",
                       "-j", "hex", "-t", root.scheme, "-m", "dark"];
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (text === "") return;
                let m;
                try {
                    m = JSON.parse(text);
                } catch (e) {
                    console.warn("Wallpaper: matugen zwrócił coś innego niż JSON:", e);
                    return;
                }
                matugen.scheme === null ? matugen.pendingSecond = m : root.save(matugen.image, matugen.scheme, m);
            }
        }
        property var pendingSecond: null
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("Wallpaper: matugen:", text.trim().split("\n")[0])
        }
        onExited: {
            // Proces nie wystartuje drugi raz z wnętrza własnego zakończenia,
            // stąd callLater.
            if (pendingSecond !== null) {
                const m = pendingSecond;
                pendingSecond = null;
                Qt.callLater(() => runSecond(m));
            } else if (priv.pending !== "") {
                // W trakcie liczenia przyszła kolejna tapeta: liczymy ostatnią.
                Qt.callLater(() => run(priv.pending));
            }
        }
    }

    // Schemat matugena → tokeny Theme. Tony z palet (pełny zakres) tam,
    // gdzie role Material nie pasują do naszych potrzeb.
    function save(image, m, second) {
        const tone = (sch, pal, t) => sch.palettes[pal][String(t)].color;
        const role = name => m.colors[name].dark.color;
        const c = {
            accent: tone(m, "primary", accentTone),
            accentBright: tone(m, "primary", accentBrightTone),
            accentDeep: tone(m, "primary", accentDeepTone),
            accentInk: tone(m, "primary", accentInkTone),
            accent2: tone(second, "primary", accentTone),
            accent2Bright: tone(second, "primary", accentBrightTone),
            surface: role("surface_container_lowest"),
            surfaceRaised: role("surface_container_low"),
            surfacePressed: role("surface_container_high"),
            text: role("on_surface"),
            textDim: tone(m, "neutral_variant", 60),
            textFaint: tone(m, "neutral_variant", 50),
            source: m.colors.source_color.dark.color
        };
        const data = { format: format, source: image, wallpaper: priv.wallpaper, scheme: scheme, colors: c };
        // Od razu, nie czekając, aż obserwacja pliku zgłosi własny zapis.
        priv.data = data;
        store.setText(JSON.stringify(data, null, 4));
        exportPalette();
    }
}
