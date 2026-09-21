pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.Common

// ---------------------------------------------------------------
// Model docka: przypięte aplikacje, uruchomione okna pogrupowane po
// aplikacji, uruchamianie, plakietki. Dock (okno) tylko to rysuje.
//
// Klucz elementu:
//   "<id .desktop>"  — aplikacja z wpisem (przypięta albo uruchomiona)
//   "wm:<appId>"     — okno, do którego nie pasuje żaden wpis .desktop
//   launcherKey / separatorKey — elementy stałe
// ---------------------------------------------------------------
Singleton {
    id: root

    // Ile czekamy na okno po uruchomieniu, zanim ikona przestanie skakać.
    property int launchTimeoutMs: 10000
    readonly property string launcherKey: "__launcher"
    readonly property string separatorKey: "__separator"

    // ---------------------------------------------------------------
    // Przypięte (Common/Pins — wspólne z launcherem)
    // ---------------------------------------------------------------

    readonly property var visiblePinned: Pins.visible

    function isSpecial(key) { return key === launcherKey || key === separatorKey; }
    function isPinned(key) { return Pins.has(key); }
    function canPin(key) { return Pins.canPin(key); }

    // ---------------------------------------------------------------
    // Okna
    // ---------------------------------------------------------------

    // ToplevelManager, tak jak DesktopEntries, zapełnia się dopiero po
    // pierwszym dotknięciu (zmierzone: 0 okien w Component.onCompleted,
    // komplet chwilę później) — to powiązanie jest tym dotknięciem.
    readonly property var toplevels: ToplevelManager.toplevels.values
    readonly property var activeToplevel: ToplevelManager.activeToplevel

    // appId okna potrafi zmienić się po zmapowaniu (gry, część Electronów),
    // a zmiana właściwości elementu listy nie przelicza powiązania z listą.
    // Licznik jest tą brakującą zależnością.
    property int appIdRevision: 0

    Instantiator {
        model: ToplevelManager.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            function onAppIdChanged() { root.appIdRevision++; }
        }
    }

    function keyForAppId(appId) {
        const e = Apps.entryForAppId(appId);
        return e ? e.id : "wm:" + (appId || "");
    }

    // { klucz: [okna, od ostatnio aktywnego] }
    readonly property var groups: {
        root.appIdRevision;
        Apps.appCount;
        priv.recentRevision;

        const recent = priv.recent;
        const rank = t => {
            const i = recent.indexOf(t);
            return i < 0 ? recent.length : i;
        };

        const g = {};
        for (let i = 0; i < toplevels.length; i++) {
            const t = toplevels[i];
            const k = keyForAppId(t.appId);
            if (!g[k]) g[k] = [];
            g[k].push(t);
        }
        for (const k in g) g[k].sort((a, b) => rank(a) - rank(b));
        return g;
    }

    readonly property string activeKey: activeToplevel ? keyForAppId(activeToplevel.appId) : ""

    function windowsFor(key) { return groups[key] || []; }
    function isRunning(key) { return windowsFor(key).length > 0; }

    // ---------------------------------------------------------------
    // Kolejność elementów
    // ---------------------------------------------------------------

    // Uruchomione, nieprzypięte — w kolejności pojawienia się, żeby ikony nie
    // przeskakiwały przy każdej zmianie fokusu.
    readonly property var runningOrder: priv.runningOrder

    onGroupsChanged: {
        const order = priv.runningOrder.filter(k => groups[k]);
        for (const k in groups) if (order.indexOf(k) < 0) order.push(k);
        if (JSON.stringify(order) !== JSON.stringify(priv.runningOrder))
            priv.runningOrder = order;

        // Uruchamiana aplikacja przestaje skakać, gdy przybędzie jej okno.
        const l = Object.assign({}, priv.launching);
        let changed = false;
        for (const k in l) {
            if (windowsFor(k).length > l[k].windows) { delete l[k]; changed = true; }
        }
        if (changed) priv.launching = l;
    }

    readonly property var items: {
        const out = [launcherKey];

        const pins = root.visiblePinned;
        for (let i = 0; i < pins.length; i++) out.push(pins[i]);

        const extra = priv.runningOrder.filter(k => pins.indexOf(k) < 0 && groups[k]);
        if (extra.length > 0) {
            out.push(separatorKey);
            for (let i = 0; i < extra.length; i++) out.push(extra[i]);
        }
        return out;
    }

    // ---------------------------------------------------------------
    // Opis elementu
    // ---------------------------------------------------------------

    function entryFor(key) {
        if (isSpecial(key) || key.startsWith("wm:")) return null;
        return Apps.entry(key);
    }

    function nameFor(key) {
        if (key === launcherKey) return "Aplikacje";
        const e = entryFor(key);
        if (e) return e.name;
        if (key.startsWith("wm:")) {
            const w = windowsFor(key);
            return w.length > 0 && w[0].title !== "" ? w[0].title : key.substring(3);
        }
        return key;
    }

    function iconFor(key) {
        if (key.startsWith("wm:")) return Apps.iconForAppId(key.substring(3));
        return Apps.iconFor(entryFor(key));
    }

    // ---------------------------------------------------------------
    // Akcje
    // ---------------------------------------------------------------

    // Główna akcja (klik). Zwraca, co się stało — "list" znaczy, że dock ma
    // pokazać listę okien, bo aplikacja jest już na wierzchu i ma ich kilka.
    function primaryAction(key) {
        const wins = windowsFor(key);
        if (wins.length === 0) {
            launch(key);
            return "launched";
        }
        if (key !== activeKey) {
            wins[0].activate();   // ostatnio używane okno tej aplikacji
            return "focused";
        }
        return wins.length > 1 ? "list" : "none";
    }

    function launch(key, action) {
        const e = entryFor(key);
        if (e) Apps.launch(e, action || null);
    }

    // Skakanie ikony zaczyna się przy KAŻDYM uruchomieniu, także z launchera
    // — stąd sygnał z Apps, a nie znacznik w launch() wyżej.
    Connections {
        target: Apps
        function onLaunched(id) {
            const l = Object.assign({}, priv.launching);
            l[id] = { at: Date.now(), windows: root.windowsFor(id).length };
            priv.launching = l;
        }
    }

    function isLaunching(key) { return priv.launching.hasOwnProperty(key); }

    // Kółko: następne / poprzednie okno aplikacji. Po STAŁEJ kolejności
    // (ToplevelManager), nie po ostatnim użyciu — po ostatnim użyciu
    // przewijanie skakałoby w kółko między dwoma oknami.
    function cycle(key, step) {
        const wins = toplevels.filter(t => keyForAppId(t.appId) === key);
        if (wins.length === 0) return;
        const cur = wins.indexOf(activeToplevel);
        const next = cur < 0 ? 0 : (cur + step + wins.length) % wins.length;
        wins[next].activate();
    }

    function closeAll(key) {
        const wins = windowsFor(key).slice();
        for (let i = 0; i < wins.length; i++) wins[i].close();
    }

    // ---------------------------------------------------------------
    // Media i rozmowa
    // ---------------------------------------------------------------

    // Aplikacje, które właśnie grają. MPRIS czytamy sami, nie przez wyspę:
    // to ta sama usługa systemowa, a wyspa wybiera JEDEN odtwarzacz, podczas
    // gdy tu chcemy znaczek przy każdym grającym. Klucz z desktopEntry
    // odtwarzacza tą samą drogą co okna ("spotify" → "spotify-launcher").
    readonly property var playingKeys: {
        Apps.appCount;
        const out = [];
        const all = Mpris.players.values;
        for (let i = 0; i < all.length; i++) {
            if (!all[i].isPlaying) continue;
            const k = keyForAppId(all[i].desktopEntry || all[i].identity);
            if (out.indexOf(k) < 0) out.push(k);
        }
        return out;
    }

    // Element, przy którym wisi znaczek rozmowy (stan z mostka Discorda wyspy).
    readonly property string callKey: { Apps.appCount; return keyForAppId("discord"); }

    // ---------------------------------------------------------------
    // Plakietki powiadomień
    // ---------------------------------------------------------------
    //
    // Wyspa trzyma historię, a my liczymy tylko to, co przyszło od chwili,
    // gdy ostatnio byłeś w tej aplikacji. Historii wyspy nie ruszamy —
    // plakietka gaśnie po wejściu do aplikacji, wpisy w wyspie zostają.
    // Momenty "widziane" w $XDG_RUNTIME_DIR, bo historia wyspy też żyje tylko
    // do restartu, a po przeładowaniu docka plakietki nie mają wracać.

    function unseenCount(key) {
        if (key === activeKey) return 0;
        const since = seen.times[key] || 0;
        return IslandLink.notificationTimes(key).filter(t => t > since).length;
    }

    onActiveKeyChanged: {
        const now = Date.now();
        const t = Object.assign({}, seen.times);
        // Poprzednia aplikacja: to, co przyszło, kiedy w niej byłeś, widziałeś.
        if (priv.lastActiveKey !== "") t[priv.lastActiveKey] = now;
        if (activeKey !== "") t[activeKey] = now;
        priv.lastActiveKey = activeKey;
        seen.times = t;
    }

    FileView {
        path: Settings.runtimeDir + "/seen.json"
        printErrors: false
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) writeAdapter();
        }

        JsonAdapter {
            id: seen
            property var times: ({})
        }
    }

    // ---------------------------------------------------------------
    // Stan prywatny
    // ---------------------------------------------------------------

    QtObject {
        id: priv

        // Okna od ostatnio aktywnego. Tablica, a nie słownik: kluczem byłby
        // obiekt okna, a słownik JS zamienia klucze na napisy.
        property var recent: []
        property int recentRevision: 0
        property var runningOrder: []
        property var launching: ({})
        property string lastActiveKey: ""
    }

    onActiveToplevelChanged: {
        const t = activeToplevel;
        if (!t) return;
        priv.recent = [t].concat(priv.recent.filter(x => x !== t && toplevels.indexOf(x) >= 0));
        priv.recentRevision++;
    }

    Timer {
        interval: 500
        running: Object.keys(priv.launching).length > 0
        repeat: true
        onTriggered: {
            const now = Date.now();
            const l = Object.assign({}, priv.launching);
            let changed = false;
            for (const k in l) {
                if (now - l[k].at > root.launchTimeoutMs) { delete l[k]; changed = true; }
            }
            if (changed) priv.launching = l;
        }
    }
}
