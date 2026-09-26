pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common

// ---------------------------------------------------------------
// Monitory: odczyt z Hyprlanda, zmiana na żywo, cofanie i zapis na stałe.
//
// Zmiana idzie przez `hyprctl eval 'hl.monitor({ … })'` — działa od razu,
// bez przeładowania konfiguracji (sprawdzone na atrapie: tryb, pozycja,
// skala, obrót, wyłączenie, klon). Każda zmiana czeka confirmSeconds na
// potwierdzenie, inaczej wraca poprzedni stan: zły tryb albo skala potrafi
// zostawić czarny ekran, na którym nie ma czego kliknąć.
//
// Zapis na stałe: reguły w monitors.json (źródło prawdy, pisze program),
// z nich generowany ~/.config/hypr/plude-monitors.lua, który hyprland.lua
// dołącza przez dofile. Hyprland stosuje go sam przy starcie i przy
// podłączeniu monitora (reguła sprzed podłączenia działa — sprawdzone),
// więc PluDE nie musi przy tym działać.
//
// Pułapki Hyprlanda (zmierzone na atrapach `hyprctl output create headless`):
// - Reguła bez `disabled = false` NIE włącza wyłączonego monitora, więc
//   zawsze wysyłamy komplet pól.
// - Skalę, przy której rozmiar logiczny nie wychodzi w całych pikselach,
//   Hyprland po cichu poprawia (1,3 przy 1920×1080 → 1,3333). Stąd validScales.
// - Klon wyłącza `mirror = ""`. W JSON-ie `mirrorOf` to id monitora, nie nazwa.
// - Stan Lua trwa między wywołaniami eval, więc require zwracałby moduł
//   z pamięci — hyprland.lua używa dofile.
// ---------------------------------------------------------------
Singleton {
    id: root

    // Czas na „Zachować?”. Po nim wraca poprzedni stan.
    property int confirmSeconds: 15
    // Strażnik poza procesem cofa zmianę trochę później niż licznik tutaj —
    // tylko wtedy, gdy powłoka zdążyła zniknąć (przeładowanie po edycji
    // pliku, awaria). Normalnie cofa licznik w QML i strażnik nie ma nic do roboty.
    property int watchdogGraceSeconds: 3
    // Zdarzenia Hyprlanda sypią się seriami (monitoradded + monitoraddedv2 + …).
    property int refreshDebounceMs: 150

    readonly property string hyprDir: Quickshell.env("HOME") + "/.config/hypr"
    readonly property string luaPath: hyprDir + "/plude-monitors.lua"

    // Monitory w kolejności Hyprlanda (id), razem z wyłączonymi:
    // { name, description, output, width, height, refreshRate, x, y, scale,
    //   transform, disabled, mirrorOf (nazwa albo ""), modes: [{ width, height, refresh }],
    //   logicalWidth, logicalHeight }
    property var monitors: []
    // Pierwszy odczyt doszedł — wcześniej pusta lista nie znaczy „brak monitorów”.
    property bool ready: false

    // ---- oczekiwanie na potwierdzenie ----

    readonly property bool pending: revertSpecs !== null
    property int confirmRemaining: 0

    signal failed(string message)

    // ---------------------------------------------------------------
    // Reguły
    // ---------------------------------------------------------------

    // Klucz reguły: opis monitora (producent, model, numer seryjny) zostaje
    // ten sam po przepięciu kabla, nazwa portu (DP-3) nie. Monitor bez opisu
    // (atrapa, uszkodzony EDID) dostaje nazwę portu.
    function outputKey(m) {
        return m.description !== "" ? "desc:" + m.description : m.name;
    }

    function modeString(width, height, refresh) {
        return width + "x" + height + "@" + refresh.toFixed(2);
    }

    // Stan monitora jako pełna reguła.
    function specOf(m) {
        return {
            output: outputKey(m),
            mode: modeString(m.width, m.height, m.refreshRate),
            position: m.x + "x" + m.y,
            scale: m.scale,
            transform: m.transform,
            disabled: m.disabled,
            mirror: m.mirrorOf
        };
    }

    function find(name) {
        for (let i = 0; i < monitors.length; i++) if (monitors[i].name === name) return monitors[i];
        return null;
    }

    // Skala w 1/120 (tak liczy protokół fractional-scale), pod warunkiem że
    // rozmiar logiczny wychodzi w całych pikselach — ten sam warunek, który
    // Hyprland sprawdza, zanim sam poprawi skalę.
    readonly property int scaleDenominator: 120

    function isValidScale(width, height, scale) {
        const k = Math.round(scale * scaleDenominator);
        if (k <= 0 || Math.abs(k / scaleDenominator - scale) > 1e-4) return false;
        return (width * scaleDenominator) % k === 0 && (height * scaleDenominator) % k === 0;
    }

    function validScales(width, height, min, max) {
        const lo = Math.ceil((min || 0.5) * scaleDenominator);
        const hi = Math.floor((max || 4) * scaleDenominator);
        const out = [];
        for (let k = lo; k <= hi; k++)
            if ((width * scaleDenominator) % k === 0 && (height * scaleDenominator) % k === 0)
                out.push(k / scaleDenominator);
        return out;
    }

    function nearestValidScale(width, height, scale) {
        const all = validScales(width, height);
        let best = 1;
        for (let i = 0; i < all.length; i++)
            if (Math.abs(all[i] - scale) < Math.abs(best - scale)) best = all[i];
        return best;
    }

    // Obrót o 90° lub 270° (także odbity) zamienia boki.
    function isRotated(transform) { return transform % 2 === 1; }

    // ---- Lua ----

    function luaString(s) {
        return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n") + "\"";
    }

    // 1/120 zaokrąglone do 6 miejsc: 1.333333 Hyprland przyjmuje bez poprawki.
    function luaScale(s) {
        const k = Math.round(s * scaleDenominator);
        return String(Math.round(k / scaleDenominator * 1e6) / 1e6);
    }

    function luaOf(spec) {
        const f = [
            "output = " + luaString(spec.output),
            "mode = " + luaString(spec.mode),
            "position = " + luaString(spec.position),
            "scale = " + luaScale(spec.scale),
            "transform = " + spec.transform,
            "disabled = " + (spec.disabled ? "true" : "false"),
            "mirror = " + luaString(spec.mirror || "")
        ];
        // VRR z JSON-a Hyprlanda to stan bieżący, nie ustawienie — wysyłamy
        // tylko jawnie zapisane, żeby nie nadpisać globalnego misc.vrr.
        if (spec.vrr !== undefined) f.push("vrr = " + spec.vrr);
        return "hl.monitor({ " + f.join(", ") + " })";
    }

    // ---------------------------------------------------------------
    // Zmiana na żywo i cofanie
    // ---------------------------------------------------------------

    // Stan sprzed PIERWSZEJ niepotwierdzonej zmiany — kolejne zmiany w tym
    // samym oknie potwierdzenia cofają się razem do niego.
    property var revertSpecs: null
    property string watchdogMarker: ""

    // specs: pełne reguły (specOf + zmiany). Monitory spoza listy zostają.
    function apply(specs) {
        if (!specs || specs.length === 0) return;
        if (revertSpecs === null) revertSpecs = monitors.map(specOf);
        // pending jest już true — licznik od razu pełny, nie po odpowiedzi eval.
        confirmRemaining = confirmSeconds;
        runEval(specs.map(luaOf).join("\n"), function (ok, message) {
            if (!ok) {
                // Błąd w środku skryptu zostawia część reguł zastosowaną.
                root.failed(message);
                root.revert();
                return;
            }
            root.confirmRemaining = root.confirmSeconds;
            countdown.restart();
            root.armWatchdog();
        });
    }

    function confirm() {
        if (!pending) return;
        countdown.stop();
        disarmWatchdog();
        revertSpecs = null;
        // Zapis z odczytu PO zmianie: tak trafia do pliku to, co Hyprland
        // naprawdę ustawił (np. poprawiona skala), a nie to, o co prosiliśmy.
        refreshThen(function () { root.saveConnected(); });
    }

    function revert() {
        if (!pending) return;
        countdown.stop();
        disarmWatchdog();
        const specs = revertSpecs;
        revertSpecs = null;
        runEval(specs.map(luaOf).join("\n"), function (ok, message) {
            if (!ok) root.failed(message);
        });
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.confirmRemaining--;
            if (root.confirmRemaining <= 0) root.revert();
        }
    }

    // Strażnik: osobny proces (execDetached — przeżywa przeładowanie
    // powłoki) cofa zmianę, jeśli po czasie jego plik znacznika wciąż
    // istnieje. Potwierdzenie i cofnięcie w QML znacznik usuwają.
    function armWatchdog() {
        disarmWatchdog();
        watchdogMarker = Settings.runtimeDir + "/monitors-pending-" + Date.now();
        const script = "mkdir -p \"$(dirname \"$2\")\" && : > \"$2\" && sleep \"$1\" "
            + "&& [ -e \"$2\" ] && rm -f \"$2\" && hyprctl eval \"$3\"";
        Quickshell.execDetached(["sh", "-c", script, "plude-monitor-watchdog",
            String(confirmSeconds + watchdogGraceSeconds), watchdogMarker,
            revertSpecs.map(luaOf).join("\n")]);
    }

    function disarmWatchdog() {
        if (watchdogMarker === "") return;
        Quickshell.execDetached(["rm", "-f", watchdogMarker]);
        watchdogMarker = "";
    }

    // ---- hyprctl eval ----

    // Jedno eval naraz; kolejne czekają w kolejce, żeby odpowiedzi nie
    // pomyliły się z wywołaniami.
    property var evalQueue: []

    function runEval(code, done) {
        evalQueue = evalQueue.concat([{ code: code, done: done }]);
        if (!evalProc.running) nextEval();
    }

    function nextEval() {
        if (evalQueue.length === 0) return;
        evalProc.job = evalQueue[0];
        evalQueue = evalQueue.slice(1);
        evalProc.command = ["hyprctl", "eval", evalProc.job.code];
        evalProc.running = true;
    }

    // Odpowiedź obsługujemy po wyjściu procesu I końcu stdout — kolejność
    // tych dwóch sygnałów nie jest gwarantowana.
    Process {
        id: evalProc
        property var job: null
        property int steps: 0
        onStarted: steps = 0
        stdout: StdioCollector {
            id: evalOut
            onStreamFinished: evalProc.step()
        }
        onExited: step()

        function step() {
            if (++steps < 2) return;
            // hyprctl kończy się kodem 0 także przy błędzie Lua — o wyniku
            // mówi dopiero treść: "ok" albo "error: …".
            const out = evalOut.text.trim();
            const ok = out === "ok";
            const job = evalProc.job;
            evalProc.job = null;
            root.refreshThen(function () {
                if (job && job.done) job.done(ok, ok ? "" : out);
            });
            root.nextEval();
        }
    }

    // ---------------------------------------------------------------
    // Odczyt
    // ---------------------------------------------------------------

    property var afterRefresh: []

    function refresh() {
        if (queryProc.running) queryProc.again = true;
        else queryProc.running = true;
    }

    function refreshThen(fn) {
        afterRefresh = afterRefresh.concat([fn]);
        refresh();
    }

    function parse(text) {
        let raw;
        try { raw = JSON.parse(text); } catch (e) { return null; }
        const byId = {};
        raw.forEach(m => byId[m.id] = m.name);
        return raw.map(m => {
            const rotated = isRotated(m.transform);
            return {
                name: m.name,
                description: m.description || "",
                output: "",
                width: m.width,
                height: m.height,
                refreshRate: m.refreshRate,
                x: m.x,
                y: m.y,
                scale: m.scale,
                transform: m.transform,
                disabled: m.disabled,
                mirrorOf: m.mirrorOf === "none" ? "" : (byId[m.mirrorOf] || m.mirrorOf),
                // "3840x2160@60.00Hz" → liczby; przy braku listy (atrapa)
                // zostaje choć bieżący tryb.
                modes: (m.availableModes && m.availableModes.length > 0 ? m.availableModes
                        : [m.width + "x" + m.height + "@" + m.refreshRate + "Hz"]).map(s => {
                    const r = /^(\d+)x(\d+)@([\d.]+)/.exec(s);
                    return r ? { width: +r[1], height: +r[2], refresh: +r[3] } : null;
                }).filter(x => x !== null),
                logicalWidth: Math.round((rotated ? m.height : m.width) / m.scale),
                logicalHeight: Math.round((rotated ? m.width : m.height) / m.scale)
            };
        }).map(m => Object.assign(m, { output: outputKey(m) }));
    }

    Process {
        id: queryProc
        property bool again: false
        property int steps: 0
        command: ["hyprctl", "monitors", "all", "-j"]
        onStarted: steps = 0
        stdout: StdioCollector {
            id: queryOut
            onStreamFinished: queryProc.step()
        }
        onExited: step()

        function step() {
            if (++steps < 2) return;
            const list = root.parse(queryOut.text);
            if (list !== null) {
                root.monitors = list;
                root.ready = true;
            }
            // Zmiana w trakcie odczytu — jeszcze raz, zanim ktoś dostanie wynik.
            if (again) {
                again = false;
                running = true;
                return;
            }
            const fns = root.afterRefresh;
            root.afterRefresh = [];
            fns.forEach(fn => fn());
        }
    }

    Timer {
        id: debounce
        interval: root.refreshDebounceMs
        onTriggered: root.refresh()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name.startsWith("monitoradded") || event.name.startsWith("monitorremoved")
                    || event.name === "configreloaded")
                debounce.restart();
        }
    }

    Component.onCompleted: refresh()

    // ---------------------------------------------------------------
    // Zapis na stałe
    // ---------------------------------------------------------------

    FileView {
        path: Settings.configDir + "/monitors.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) writeAdapter();
        }

        JsonAdapter {
            id: store
            // { "<desc:… albo nazwa portu>": reguła jak w specOf }
            // Reguły monitorów, których teraz nie ma (druga maszyna,
            // monitor w pracy), zostają — generowany plik ma je wszystkie.
            property var rules: ({})
        }
    }

    readonly property var rules: store.rules

    // Całe podłączone ustawienie naraz: pozycje monitorów zależą od siebie,
    // więc zapis tylko zmienionego zostawiłby resztę na łasce „auto”.
    function saveConnected() {
        const r = Object.assign({}, store.rules);
        monitors.forEach(m => {
            const spec = specOf(m);
            // Pola spoza stanu (vrr) z poprzedniej reguły zostają.
            r[spec.output] = Object.assign({}, r[spec.output] || {}, spec);
        });
        store.rules = r;
        writeLua();
    }

    function forget(output) {
        const r = Object.assign({}, store.rules);
        delete r[output];
        store.rules = r;
        writeLua();
    }

    function luaFile() {
        const keys = Object.keys(store.rules).sort();
        return [
            "-- Wygenerowane przez PluDE (Ustawienia → Monitory). Nie edytuj: plik",
            "-- jest nadpisywany przy każdym zatwierdzeniu. Źródło: ~/.config/plude/monitors.json.",
            "-- Dołączany na końcu sekcji MONITORS w hyprland.lua (dofile).",
            ""
        ].concat(keys.map(k => luaOf(store.rules[k]))).join("\n") + "\n";
    }

    function writeLua() { luaView.setText(luaFile()); }

    FileView {
        id: luaView
        path: root.luaPath
        blockLoading: false
        // Nie czytamy go — plik tylko piszemy.
        preload: false
    }
}
