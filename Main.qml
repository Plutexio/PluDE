import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common
import qs.PluAppDock
import qs.PluLauncher

// Właściwa powłoka, ładowana przez shell.qml tylko na Hyprlandzie.
Item {
    // Dock i launcher na jednym monitorze (Settings.dockScreen, domyślnie
    // automat jak w wyspie). Bez Variants: jeden dock, nie po jednym na ekran.
    Dock {}
    Launcher {}

    // ---- sterowanie z zewnątrz ----
    //
    //   qs -p ~/PluDE ipc call launcher toggle
    IpcHandler {
        target: "launcher"

        function toggle(): void { LauncherService.toggle(); }
        function show(): void { LauncherService.show(); }
        function hide(): void { LauncherService.hide(); }
    }

    // Skrót globalny — klawisz przypisuje Hyprland (hyprland.lua):
    //   hl.bind(mainMod .. " + R", hl.dsp.global("quickshell:launcherToggle"))
    GlobalShortcut {
        appid: "quickshell"
        name: "launcherToggle"
        description: "Pokaż / ukryj launcher PluDE"

        onPressed: LauncherService.toggle()
    }
}
