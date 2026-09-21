pragma Singleton

import QtQuick
import Quickshell

// ---------------------------------------------------------------
// Wpisy .desktop: wyszukiwanie, dopasowanie okna do aplikacji, ikony
// i uruchamianie. Wspólne dla docka i launchera — oba muszą tak samo
// rozumieć "która to aplikacja", inaczej przypięcie z launchera
// nie trafiłoby w okno widoczne w docku.
// ---------------------------------------------------------------
Singleton {
    id: root

    // DesktopEntries skanuje asynchronicznie i dopiero przy PIERWSZYM
    // dotknięciu (zmierzone: 0 wpisów przy pierwszym odczycie, 47 po ~2 s).
    // To powiązanie jest tym dotknięciem i zarazem zależnością, po której
    // przeliczają się wszystkie dopasowania — samo wołanie funkcji nie jest
    // zależnością i po dojechaniu listy nic by się nie odświeżyło.
    readonly property int appCount: DesktopEntries.applications.values.length
    readonly property bool ready: appCount > 0

    // Aplikacje do pokazania w launcherze: bez NoDisplay=true (pomocnicze
    // wpisy typu "kitty-open", obsługa URL-i).
    readonly property var visibleApps: {
        const all = DesktopEntries.applications.values;
        return all.filter(e => !e.noDisplay);
    }

    // Każda funkcja szukająca wpisu CZYTA appCount: wtedy powiązanie, które
    // ją woła (ikona w docku, nazwa), przelicza się po dojechaniu listy.
    // Bez tego delegaty utworzone przed skanem zostawały z ikoną zastępczą
    // na zawsze (zmierzone: wszystkie przypięte z "!" po starcie).
    function entry(id) {
        root.appCount;
        if (!id || id === "") return null;
        return DesktopEntries.byId(id);
    }

    // ---- okno → wpis .desktop ----
    //
    // appId okna bywa zapisane inaczej niż id wpisu: "dolphin" przy
    // "org.kde.dolphin", "Spotify" przy "spotify-launcher", klasa w
    // StartupWMClass. Kolejność: dokładne id → id bez wielkości liter →
    // StartupWMClass → ostatni człon id → heurystyka Quickshella.
    // Dopasowujemy WYŁĄCZNIE po appId, nigdy po tytule (lekcja z wyspy:
    // "Discord" w tytule karty przeglądarki to nie Discord).
    QtObject {
        id: priv
        property var cache: ({})
    }
    onAppCountChanged: priv.cache = ({})

    function entryForAppId(appId) {
        root.appCount;
        if (!appId || appId === "") return null;
        if (priv.cache.hasOwnProperty(appId)) return priv.cache[appId];

        const found = lookup(appId);
        // Pustej listy nie zapamiętujemy — przed skanem każdy wynik to null.
        if (ready) priv.cache[appId] = found;
        return found;
    }

    function lookup(appId) {
        let e = DesktopEntries.byId(appId);
        if (e) return e;

        const low = appId.toLowerCase();
        e = DesktopEntries.byId(low);
        if (e) return e;

        const all = DesktopEntries.applications.values;
        for (let i = 0; i < all.length; i++) {
            const wm = (all[i].startupClass || "").toLowerCase();
            if (wm !== "" && wm === low) return all[i];
        }
        for (let i = 0; i < all.length; i++) {
            const last = all[i].id.toLowerCase().split(".").pop();
            if (last === low) return all[i];
        }
        return DesktopEntries.heuristicLookup(appId);
    }

    // ---- ikony ----
    //
    // Ścieżka ikony albo pusty string. Ikona może być nazwą z motywu albo
    // bezwzględną ścieżką (AppImage, gry ze Steama).
    function iconFor(e) {
        if (!e || !e.icon || e.icon === "") return Quickshell.iconPath("application-x-executable", true);
        if (e.icon.startsWith("/")) return "file://" + e.icon;
        return Quickshell.iconPath(e.icon, "application-x-executable");
    }

    function iconForAppId(appId) {
        const e = entryForAppId(appId);
        if (e) return iconFor(e);
        // Okno bez wpisu .desktop — czasem motyw ma ikonę o nazwie appId.
        if (appId && Quickshell.hasThemeIcon(appId)) return Quickshell.iconPath(appId);
        return Quickshell.iconPath("application-x-executable", true);
    }

    // ---- uruchamianie ----

    signal launched(string id)

    // action = DesktopAction albo null. Terminal=true obsługujemy sami:
    // execute() uruchamia polecenie wprost, a htop bez terminala nie ma
    // gdzie się narysować.
    function launch(e, action) {
        if (!e) return false;
        const target = action || e;

        if (e.runInTerminal) {
            Quickshell.execDetached({
                command: [Settings.terminal, "-e"].concat(target.command),
                workingDirectory: e.workingDirectory || Quickshell.env("HOME")
            });
        } else {
            target.execute();
        }

        root.launched(e.id);
        return true;
    }
}
