pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common

// ---------------------------------------------------------------
// Zrzuty ekranu: slurp wybiera obszar, grim robi zrzut, swappy go edytuje,
// wl-copy wkłada do schowka, tesseract czyta z niego tekst. Tutaj jest
// kolejność tych kroków.
//
// Gotowy zrzut (i błąd) zgłasza wyspa jako zwykłe powiadomienie z akcjami.
// Gdy wyspa nie żyje albo jest schowana, robi to podgląd w rogu (ShotToast).
//
// Tryby:
//   region  zaznaczenie myszą, a klik w okno albo pusty ekran bierze je całe
//   window  aktywne okno, od razu
//   screen  monitor z fokusem, od razu
//   text    zaznaczenie jak w region, ale do schowka idzie rozpoznany tekst
//           (OCR), a obraz nigdzie się nie zapisuje
// ---------------------------------------------------------------
Singleton {
    id: root

    // Po schowaniu podglądu, zanim grim złapie ekran: warstwa musi zdążyć zniknąć.
    property int settleMs: 140
    // Wygląd zaznaczania w slurpie: przyciemnienie jak pod launcherem,
    // zaznaczony obszar bez przyciemnienia, obrys w akcencie.
    property real dim: 0.45
    property int borderWidth: 2
    // Kompresja PNG (0–9). Domyślna szóstka grima to 2,2 s na ekran 4K, zanim
    // cokolwiek widać. Zmierzone: 1 → 0,76 s i plik większy o jedną czwartą.
    property int pngLevel: 1
    // Tyle notify-send czeka na klik w akcję powiadomienia. Wyspa nie wygasza
    // powiadomień z historii, więc bez limitu proces wisiałby do jej wyczyszczenia.
    property int actionWaitSeconds: 3600

    // Tyle znaków rozpoznanego tekstu pokazuje podgląd w rogu (i powiadomienie
    // przy wyspie bez zerknięć), a tyle zerknięcie w pigułce wyspy.
    property int previewChars: 180
    property int glanceChars: 48

    readonly property var tools: ["grim", "slurp", "swappy", "wl-copy"]
    // Których narzędzi brakuje w PATH. Sprawdzane przy starcie i po nieudanym zrzucie.
    property var missing: []
    readonly property var ocrTools: ["tesseract"]
    // Rozpoznawanie tekstu osobno: bez tesseracta zwykłe zrzuty działają dalej.
    property bool ocrMissing: false
    // Języki zainstalowane dla tesseracta (paczki tesseract-data-*), bez osd.
    property var ocrInstalled: []
    // Języki z ustawień, które da się użyć. Tesseract z niezainstalowanym
    // językiem kończy się błędem, więc zostają tylko zainstalowane; gdy z
    // ustawień nie zostaje nic, angielski albo pierwszy zainstalowany.
    readonly property var ocrLanguages: {
        const wanted = Settings.ocrLanguages.split("+").filter(l => l !== "");
        if (ocrInstalled.length === 0) return wanted.length > 0 ? wanted : ["eng"];
        const usable = wanted.filter(l => ocrInstalled.indexOf(l) >= 0);
        if (usable.length > 0) return usable;
        return [ocrInstalled.indexOf("eng") >= 0 ? "eng" : ocrInstalled[0]];
    }

    property bool busy: false
    // Odliczanie przed zrzutem z opóźnieniem (sekundy do zrzutu, 0 = brak).
    property int countdown: 0
    // Ostatni zrzut: { path, copied } albo null.
    property var last: null

    // Podgląd w rogu jest na ekranie: przed zrzutem trzeba go schować i odczekać.
    property bool toastShown: false
    // Monitor z fokusem przy ostatnim zrzucie: tam pokazuje się podgląd.
    property var screen: null

    // Powiązanie, nie odczyt w capture(): Hyprland w Quickshellu zapełnia się
    // dopiero po pierwszym dotknięciu (zmierzone: null przy pierwszym odczycie).
    readonly property var focusedMonitor: Hyprland.focusedMonitor

    readonly property bool viaIsland: IslandLink.alive && !IslandLink.islandHidden

    signal starting()
    // Oba tylko dla ShotToast: emitowane, gdy wyspa nie przejmuje komunikatu.
    signal captured(string path)
    signal recognized(string text)
    signal failed(string reason)

    Component.onCompleted: checkTools()

    // ---------------------------------------------------------------
    // Zrzut
    // ---------------------------------------------------------------

    property string mode: ""

    function newPath() {
        return Settings.screenshotDir + "/Zrzut ekranu " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH-mm-ss") + ".png";
    }

    function capture(mode) {
        if (busy) return;
        if (["region", "window", "screen", "text"].indexOf(mode) < 0) {
            console.warn("ScreenshotService.capture: nie ma trybu " + mode);
            return;
        }
        countdownTimer.stop();
        countdown = 0;
        busy = true;
        root.mode = mode;

        screen = focusedMonitor ? (Quickshell.screens.find(s => s.name === focusedMonitor.name) ?? null) : null;

        const wasShown = toastShown;
        starting();
        if (wasShown) settle.restart();
        else query.running = true;
    }

    // Zrzut za `seconds` sekund, z odliczaniem w rogu (menu, które znika
    // przy wciśnięciu klawisza, da się tak złapać).
    function delayed(mode, seconds) {
        if (busy) return;
        if (seconds <= 0) {
            capture(mode);
            return;
        }
        root.mode = mode;
        countdown = seconds;
        countdownTimer.restart();
    }

    function cancelCountdown() {
        countdownTimer.stop();
        countdown = 0;
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (--root.countdown > 0) return;
            stop();
            root.capture(root.mode);
        }
    }

    Timer {
        id: settle
        interval: root.settleMs
        onTriggered: query.running = true
    }

    // Monitory, okna i aktywne okno jednym procesem: z nich powstają pola
    // do kliknięcia w slurpie i geometria aktywnego okna. Odpowiedź obsługujemy
    // po wyjściu procesu I końcu stdout (kolejność nie jest gwarantowana).
    Process {
        id: query
        property int steps: 0
        command: ["sh", "-c", "hyprctl -j monitors; echo @@; hyprctl -j clients; echo @@; hyprctl -j activewindow"]
        onStarted: steps = 0
        stdout: StdioCollector {
            id: queryOut
            onStreamFinished: query.step()
        }
        onExited: step()

        function step() {
            if (++steps < 2) return;
            let parts;
            try {
                parts = queryOut.text.split("\n@@\n").map(t => JSON.parse(t));
            } catch (e) {
                root.fail("Hyprland nie podał listy okien.");
                return;
            }
            root.shoot(parts[0], parts[1], parts[2]);
        }
    }

    function geometry(x, y, w, h) { return x + "," + y + " " + w + "x" + h; }

    // Pola dla slurpa: okna widocznych obszarów roboczych, potem całe monitory.
    // Slurp bierze pierwsze pole pod kursorem, więc kolejność to kolejność
    // „co jest na wierzchu”: obszar specjalny, okna pływające, kafelki, monitor.
    function boxes(monitors, clients) {
        const special = monitors.map(m => m.specialWorkspace ? m.specialWorkspace.id : 0).filter(id => id !== 0);
        const active = monitors.map(m => m.activeWorkspace.id);
        const rank = c => special.indexOf(c.workspace.id) >= 0 ? 0 : c.floating ? 1 : 2;

        const out = clients
            .filter(c => c.mapped && !c.hidden && (special.indexOf(c.workspace.id) >= 0 || active.indexOf(c.workspace.id) >= 0))
            .sort((a, b) => rank(a) - rank(b) || a.focusHistoryID - b.focusHistoryID)
            .map(c => geometry(c.at[0], c.at[1], c.size[0], c.size[1]));
        monitors.forEach(m => {
            // Rozmiar logiczny: piksele podzielone przez skalę, obrócony monitor ma boki zamienione.
            const turned = m.transform % 2 === 1;
            const w = Math.round((turned ? m.height : m.width) / m.scale);
            const h = Math.round((turned ? m.width : m.height) / m.scale);
            out.push(geometry(m.x, m.y, w, h));
        });
        return out;
    }

    function hex(c, alpha) {
        const part = v => ("0" + Math.round(v * 255).toString(16)).slice(-2);
        return part(c.r) + part(c.g) + part(c.b) + part(alpha);
    }

    property string pendingPath: ""

    function shoot(monitors, clients, activeWindow) {
        let arg = "";
        if (mode === "region" || mode === "text") {
            arg = boxes(monitors, clients).join("\n");
        } else if (mode === "window") {
            if (!activeWindow || !activeWindow.size) {
                fail("Nie ma aktywnego okna.");
                return;
            }
            arg = geometry(activeWindow.at[0], activeWindow.at[1], activeWindow.size[0], activeWindow.size[1]);
        } else {
            const mon = monitors.find(m => m.focused) || monitors[0];
            arg = mon.name;
        }

        // Tekst: obraz tylko na chwilę, w tmpfs, i bez kompresji (zmierzone:
        // poziom 0 to 0,18 s na ekran 4K, a plik i tak zaraz znika). Kursor
        // zasłaniałby litery.
        const text = mode === "text";
        pendingPath = text ? Settings.runtimeDir + "/ocr.png" : newPath();
        // Kody wyjścia: 10 = zaznaczanie anulowane (Esc), 127 = brak narzędzia
        // (nazwa na stdout), 4 = błąd tesseracta, reszta = błąd grima.
        // W trybie text na stdout jest rozpoznany tekst.
        const script = "out=$1; mode=$2; arg=$3; level=$4; cursor=$5; langs=$6; shift 6\n"
            + "need() { command -v \"$1\" > /dev/null 2>&1 || { echo \"$1\"; exit 127; }; }\n"
            + "need grim\n"
            + "mkdir -p \"$(dirname \"$out\")\" || exit 3\n"
            + "case $mode in\n"
            + "region) need slurp; geom=$(printf '%s\\n' \"$arg\" | slurp \"$@\") || exit 10\n"
            + "    grim -l \"$level\" $cursor -g \"$geom\" \"$out\" ;;\n"
            + "window) grim -l \"$level\" $cursor -g \"$arg\" \"$out\" ;;\n"
            + "screen) grim -l \"$level\" $cursor -o \"$arg\" \"$out\" ;;\n"
            + "text) need slurp; need tesseract; geom=$(printf '%s\\n' \"$arg\" | slurp \"$@\") || exit 10\n"
            + "    grim -l 0 -g \"$geom\" \"$out\" || exit 2\n"
            + "    tesseract \"$out\" - -l \"$langs\" 2> /dev/null; c=$?; rm -f \"$out\"; [ $c -eq 0 ] || exit 4 ;;\n"
            + "esac";
        shot.command = ["sh", "-c", script, "plude-shot", pendingPath, mode, arg, String(pngLevel),
            Settings.screenshotCursor && !text ? "-c" : "", ocrLanguages.join("+"),
            "-d", "-w", String(borderWidth),
            "-b", hex(Qt.rgba(0, 0, 0, 1), dim),
            "-c", hex(Theme.accent, 1),
            "-s", "00000000",
            "-B", hex(Theme.accent, 0.14)];
        shot.running = true;
    }

    Process {
        id: shot
        property int steps: 0
        onStarted: steps = 0
        stdout: StdioCollector {
            id: shotOut
            onStreamFinished: shot.step()
        }
        onExited: code => { shot.code = code; shot.step(); }
        property int code: 0

        function step() {
            if (++steps < 2) return;
            const tool = shotOut.text.trim();
            if (code === 0 && root.mode === "text") root.doneText(shotOut.text);
            else if (code === 0) root.done(root.pendingPath);
            else if (code === 10) root.busy = false;
            else if (code === 127 && tool === "tesseract") {
                root.checkTools();
                root.fail("Brak programu tesseract. Zainstaluj: sudo pacman -S tesseract tesseract-data-pol tesseract-data-eng");
            } else if (code === 127) {
                root.checkTools();
                root.fail("Brak programu " + tool + ". Zainstaluj: grim, slurp, swappy.");
            } else if (code === 4) {
                // Najczęściej brak danych języka: lista mogła się zmienić od startu.
                root.checkTools();
                root.fail("tesseract nie odczytał tekstu (języki: " + root.ocrLanguages.join(", ") + ").");
            } else root.fail("grim nie zrobił zrzutu (kod " + code + ").");
        }
    }

    function fail(reason) {
        busy = false;
        report(reason);
    }

    function report(reason) {
        if (!viaIsland) {
            failed(reason);
            return;
        }
        Quickshell.execDetached(["notify-send", "-a", "Zrzut ekranu", "-u", "critical",
            "-h", "string:desktop-entry:plude-screenshot-notice",
            mode === "text" ? "Nie udało się odczytać tekstu" : "Zrzut się nie udał", reason]);
    }

    // Powiadomienie w wyspie: miniatura zrzutu jako ikona, klik otwiera edytor,
    // przyciski to te same akcje co w podglądzie. notify-send wypisuje nazwę
    // wybranej akcji, a ta wraca do nas przez IPC (act). Osobny proces, żeby
    // akcje działały też po przeładowaniu powłoki.
    function announce(path, copied) {
        const script = "a=$(timeout \"$4\" notify-send -a 'Zrzut ekranu' -i \"$1\""
            + " -h string:desktop-entry:plude-screenshot-notice"
            + " -A default=Edytuj -A edit=Edytuj -A folder=Katalog -A delete=Usuń"
            + " 'Zrzut zapisany' \"$2\") || exit 0\n"
            + "[ -n \"$a\" ] && qs -p \"$3\" ipc call screenshot act \"$a\" \"$1\"";
        Quickshell.execDetached(["sh", "-c", script, "plude-shot", path,
            copied ? "Skopiowany do schowka" : path.replace(/^.*\//, ""),
            Quickshell.shellDir, String(actionWaitSeconds)]);
    }

    // Akcja z powiadomienia wyspy (IPC).
    function act(action, path) {
        if (action === "default" || action === "edit") edit(path, path);
        else if (action === "folder") reveal(path);
        else if (action === "delete") remove(path);
    }

    function done(path) {
        busy = false;
        last = { path: path, copied: Settings.screenshotCopy };
        if (Settings.screenshotCopy) copy(path);
        if (Settings.screenshotEdit) edit(path, path);
        else if (viaIsland) announce(path, Settings.screenshotCopy);
        else captured(path);
    }

    // Tesseract dzieli strony znakiem \f i zostawia spacje na końcach wierszy.
    function doneText(raw) {
        busy = false;
        const text = raw.replace(/\f/g, "").replace(/[ \t]+$/gm, "").replace(/^\s*\n/, "").replace(/\s+$/, "");
        if (text === "") {
            if (viaIsland) glance("warning", "Brak tekstu w zaznaczeniu", "", "Nie udało się odczytać tekstu",
                                  "W zaznaczeniu nie ma tekstu, który dałoby się odczytać.");
            else failed("W zaznaczeniu nie ma tekstu, który dałoby się odczytać.");
            return;
        }
        // wl-copy z tekstem w argumentach, nie przez potok: nie dokleja końca
        // linii, a tekst trafia też do historii schowka jak każde skopiowanie.
        Quickshell.execDetached(["wl-copy", "--", text]);
        // Pierwszy wiersz w zerknięciu: pigułka ma jedną linię.
        if (viaIsland) glance("check", preview(text.split("\n")[0], glanceChars), "w schowku",
                              "Tekst skopiowany do schowka", preview(text, previewChars));
        else recognized(text);
    }

    function preview(text, chars) {
        return text.length > chars ? text.slice(0, chars).replace(/\s+$/, "") + "…" : text;
    }

    // Zerknięcie w zwiniętej pigułce wyspy (`ipc call island glance`): tekst
    // w schowku to drobiazg, który nie potrzebuje miejsca w historii
    // powiadomień. Wyspa sprzed zerknięć odpowiada „Function not found.”
    // z kodem 0, więc o wyniku mówi wyjście, a nie kod: cokolwiek wypisane
    // (także brak instancji) = zwykłe powiadomienie. Jego treść idzie przez
    // znaczniki (bodyMarkupSupported), a tekst potrafi mieć „<” i „&”.
    function glance(icon, title, value, fallbackTitle, fallbackBody) {
        const script = "out=$(qs -p \"$1\" ipc call island glance \"$2\" \"$3\" \"$4\" 2>&1)\n"
            + "[ -z \"$out\" ] || notify-send -a 'Zrzut ekranu' -h string:desktop-entry:plude-screenshot-notice \"$5\" \"$6\"";
        Quickshell.execDetached(["sh", "-c", script, "plude-shot", Settings.islandPath, icon, title, value, fallbackTitle,
            fallbackBody.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")]);
    }

    // ---------------------------------------------------------------
    // Akcje na gotowym zrzucie
    // ---------------------------------------------------------------

    function copy(path) {
        Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "plude-shot", path]);
    }

    // Edycja w swappy. Wynik zapisuje się do `output` przy zamknięciu edytora
    // (dla zrzutu to ten sam plik, dla obrazu z historii schowka nowy)
    // i wraca do schowka. Osobny proces: edytor ma przeżyć przeładowanie powłoki.
    function edit(source, output) {
        if (missing.indexOf("swappy") >= 0) {
            report("Brak programu swappy.");
            return;
        }
        const script = "mkdir -p \"$(dirname \"$2\")\" && swappy -f \"$1\" -o \"$2\" && [ \"$3\" = 1 ] && [ -s \"$2\" ] && wl-copy --type image/png < \"$2\"";
        Quickshell.execDetached(["sh", "-c", script, "plude-shot", source, output, Settings.screenshotCopy ? "1" : "0"]);
    }

    function reveal(path) {
        Quickshell.execDetached(["xdg-open", path.replace(/\/[^\/]*$/, "")]);
    }

    function remove(path) {
        Quickshell.execDetached(["rm", "-f", "--", path]);
        if (last && last.path === path) last = null;
    }

    // ---------------------------------------------------------------
    // Narzędzia
    // ---------------------------------------------------------------

    function checkTools() { toolCheck.running = true; }

    // Brakujące programy, potem po „@@” języki tesseracta. Nagłówek listy
    // języków („List of available languages…”) odpada na filtrze kodów.
    Process {
        id: toolCheck
        command: ["sh", "-c", "for c in \"$@\"; do command -v \"$c\" > /dev/null 2>&1 || echo \"$c\"; done; echo @@\n"
            + "command -v tesseract > /dev/null 2>&1 && tesseract --list-langs 2> /dev/null", "plude-tools"].concat(root.tools, root.ocrTools)
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("@@\n");
                const absent = parts[0].split("\n").filter(t => t !== "");
                root.missing = absent.filter(t => root.tools.indexOf(t) >= 0);
                root.ocrMissing = absent.indexOf("tesseract") >= 0;
                root.ocrInstalled = (parts[1] ?? "").split("\n").filter(l => /^[A-Za-z_]+$/.test(l) && l !== "osd");
            }
        }
    }
}
