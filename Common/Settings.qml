pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ---------------------------------------------------------------
// Ustawienia: ~/.config/plude/settings.json. Pisze je okno ustawień
// (set), ale plik da się dalej edytować ręcznie. Brak pliku → zapis
// domyślnych, więc po pierwszym starcie jest co edytować. Zmiany w pliku
// wchodzą na żywo (watchChanges).
//
// Przypięte aplikacje NIE siedzą tutaj, tylko w dock.json (DockService):
// tamten plik zmienia się przy każdym przypięciu i przeciągnięciu, a ten
// tylko wtedy, gdy ktoś świadomie zmienia ustawienie.
// ---------------------------------------------------------------
Singleton {
    id: root

    readonly property string configDir: Quickshell.env("HOME") + "/.config/plude"
    // Stan ulotny (co widziałeś, stan wyspy) — w tmpfs, znika z restartem
    // systemu razem z historią powiadomień wyspy, której dotyczy.
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") + "/plude"

    // Monitor docka po nazwie (hyprctl monitors). Pusto = ten sam automat co
    // w wyspie: ekran w punkcie (0,0), potem pierwszy z listy. Nie wpisuj
    // nazwy na stałe w kodzie — projekt chodzi na dwóch maszynach.
    readonly property alias dockScreen: data.dockScreen
    // Terminal dla wpisów .desktop z Terminal=true (htop, btop…).
    readonly property alias terminal: data.terminal
    // Katalog konfiguracji wyspy — pod nim idą polecenia IPC do niej.
    readonly property string islandPath: data.islandPath.replace(/^~/, Quickshell.env("HOME"))
    // Tak, jak stoi w pliku (z ~) — do pokazania w oknie ustawień.
    readonly property alias islandPathRaw: data.islandPath
    // Schowanie wyspy skrótem chowa też dock.
    readonly property alias hideWithIsland: data.hideWithIsland
    // Pasek u góry rezerwuje miejsce: okna zaczynają się pod nim. false =
    // pasek unosi się nad oknami jak wyspa.
    readonly property alias barReserve: data.barReserve

    // Zmiana z okna ustawień. Zapis idzie sam (onAdapterUpdated), a
    // powiązania z aliasami wyżej przeliczają się od razu.
    function set(key, value) {
        if (data[key] === undefined) {
            console.warn("Settings.set: nie ma ustawienia " + key);
            return;
        }
        if (data[key] !== value) data[key] = value;
    }

    FileView {
        path: root.configDir + "/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) writeAdapter();
        }

        JsonAdapter {
            id: data

            property string dockScreen: ""
            property string terminal: "kitty"
            property string islandPath: "~/PluDynamicIsland"
            property bool hideWithIsland: true
            property bool barReserve: true
        }
    }

    // Ekran wg nazwy albo automat. Wspólne dla docka i launchera, żeby oba
    // lądowały na tym samym monitorze.
    function pickScreen(name) {
        const all = Quickshell.screens;
        if (name && name !== "") {
            const named = all.filter(s => s.name === name);
            if (named.length > 0) return named[0];
        }
        // Kolejność Quickshell.screens NIE odpowiada priorytetom kompozytora
        // (zmierzone w wyspie na KDE) — monitor główny stoi w (0,0).
        const atOrigin = all.filter(s => s.x === 0 && s.y === 0);
        if (atOrigin.length > 0) return atOrigin[0];
        return all.length > 0 ? all[0] : null;
    }

    readonly property var screen: pickScreen(dockScreen)
}
