pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ---------------------------------------------------------------
// Łącznik z wyspą (~/PluDynamicIsland), która chodzi jako OSOBNY proces.
//
// Stan wyspa → my: plik $XDG_RUNTIME_DIR/plude/island.json, który wyspa
// przepisuje przy zmianie (jej DockLink.qml). Plik, a nie powiadomienia
// przez IPC, bo zrestartowany dock ma od razu dostać aktualny stan —
// powiadomienie wysłane w trakcie naszego restartu przepadłoby.
//
// Polecenia my → wyspa: `qs -p <wyspa> ipc call island …`.
//
// Kluczem aplikacji po obu stronach jest id wpisu .desktop — wyspa
// rozwiązuje je tą samą drogą (desktop-entry z powiadomienia, potem
// heurystyka), więc "discord" tutaj to "discord" tam.
// ---------------------------------------------------------------
Singleton {
    id: root

    // Stan uznajemy za martwy, gdy wyspa nie przepisała pliku tyle czasu
    // (wyspa odświeża go co heartbeatMs nawet bez zmian). Inaczej po
    // zamknięciu wyspy plakietki wisiałyby do końca świata.
    property int staleAfterMs: 15000
    // Po tylu ms bez świeżego stanu czytamy plik sami (patrz Timer niżej).
    // Nieco więcej niż heartbeat wyspy (5 s).
    property int reloadAfterMs: 6000

    readonly property bool alive: priv.alive
    // { "<id .desktop>": [czas epoch ms, …] } — wpisy w historii wyspy.
    readonly property var notifications: priv.alive ? (priv.state.notifications || {}) : ({})
    // { "<id .desktop>": { progress: 0–1, count: n } } — trwające transfery.
    readonly property var jobs: priv.alive ? (priv.state.jobs || {}) : ({})
    readonly property var discord: priv.alive ? (priv.state.discord || null) : null
    readonly property bool islandHidden: priv.alive && !!priv.state.hidden

    function notificationTimes(id) { return notifications[id] || []; }
    function jobFor(id) { return jobs[id] || null; }

    // ---- polecenia do wyspy ----

    function call(fn, args) {
        Quickshell.execDetached(["qs", "-p", Settings.islandPath, "ipc", "call", "island", fn]
                                .concat(args || []));
    }

    // Pokazuje kartę powiadomień (opcjonalnie tylko z jednej aplikacji —
    // wyspa na razie pokazuje całą historię, id idzie na przyszłość).
    function showNotifications(id) { call("showNotifications", [id || ""]); }

    // Otwiera nakładkę Wi-Fi / Bluetooth w wyspie, a drugi raz ją zamyka
    // ("wifi" | "bluetooth"). Pasek u góry: klik w ikonę sieci.
    function toggleOverlay(mode) { call("toggleOverlay", [mode]); }

    // ---- odczyt stanu ----

    QtObject {
        id: priv
        property var state: ({})
        property double lastUpdate: 0
        property bool alive: false
    }

    function checkAlive() {
        priv.alive = priv.lastUpdate > 0 && Date.now() - priv.lastUpdate < root.staleAfterMs;
    }

    FileView {
        id: file
        path: Settings.runtimeDir + "/island.json"
        watchChanges: true
        printErrors: false   // brak pliku = wyspa nie działa albo nie ma DockLinka; to nie błąd

        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text());
                priv.state = s;
                priv.lastUpdate = s.updated || 0;
            } catch (e) {
                // Plik w trakcie zapisu albo uszkodzony — zostaje poprzedni stan.
            }
            root.checkAlive();
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        // watchChanges nie obserwuje pliku, którego jeszcze nie ma. Przy
        // starcie sesji dock rusza razem z wyspą, przed jej pierwszym zapisem,
        // i bez tego zostawał z alive = false do restartu (zmierzone sondą).
        onTriggered: {
            if (Date.now() - priv.lastUpdate > root.reloadAfterMs) file.reload();
            root.checkAlive();
        }
    }
}
