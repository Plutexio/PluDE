pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// ---------------------------------------------------------------
// Stan okna ustawień: czy jest otwarte i na której stronie. Main.qml
// trzyma okno w LazyLoaderze powiązanym z `shown`, więc zamknięte okno
// nic nie kosztuje. Otwierają je: IPC (settings), prawy klik na
// zasilaniu w pasku, wpis „Ustawienia PluDE” w launcherze.
// ---------------------------------------------------------------
Singleton {
    id: root

    // Hyprland rozpoznaje okno po tytule (reguła w hyprland.lua: pływające,
    // wyśrodkowane) — klasa to zawsze org.quickshell, a FloatingWindow nie
    // ma appId. Zmieniasz tytuł → zmień regułę.
    readonly property string windowTitle: "Ustawienia PluDE"

    readonly property var pages: [
        { id: "general", title: "Ogólne", icon: "tune" },
        { id: "monitors", title: "Monitory", icon: "computer" },
        { id: "capture", title: "Schowek i zrzuty", icon: "paste" }
    ]

    property bool shown: false
    property string page: "general"
    // Wspólna lista wyboru okna (ChoiceMenu); ustawia ją SettingsWindow.
    property var menu: null

    function open(pageId) {
        if (pageId && pages.some(p => p.id === pageId)) page = pageId;
        // Już otwarte (np. pod innymi oknami) → tylko na wierzch. Wybór po
        // tytule bez ^…$ — z kotwicami fokus nie przechodził (zmierzone).
        if (shown) Hyprland.dispatch("hl.dsp.focus({ window = \"title:" + windowTitle + "\" })");
        shown = true;
    }

    function close() { shown = false; }
    function toggle() { if (shown) close(); else open(""); }
}
