import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common
import qs.PluAppDock
import qs.PluBar
import qs.PluLauncher
import qs.PluSettings

// Właściwa powłoka, ładowana przez shell.qml tylko na Hyprlandzie.
Item {
    // Dock i launcher na jednym monitorze (Settings.dockScreen, domyślnie
    // automat jak w wyspie). Bez Variants: jeden dock, nie po jednym na ekran.
    Dock {}
    Launcher {}
    Bar {}

    // Okno ustawień tylko wtedy, gdy otwarte: zamknięte nic nie kosztuje,
    // a każde otwarcie zaczyna od czystego stanu.
    LazyLoader {
        active: SettingsApp.shown
        SettingsWindow {}
    }

    // ---- sterowanie z zewnątrz ----
    //
    //   qs -p ~/PluDE ipc call launcher toggle
    IpcHandler {
        target: "launcher"

        function toggle(): void { LauncherService.toggle(); }
        function show(): void { LauncherService.show(); }
        function hide(): void { LauncherService.hide(); }
    }

    // Klawisze jasności (hyprland.lua) — brightnessctl nie jest zainstalowany,
    // a zapis przez logind i tak siedzi w pasku:
    //   qs -p ~/PluDE ipc call bar brightnessStep 5
    IpcHandler {
        target: "bar"

        function brightnessStep(percent: int): void { Brightness.stepBy(percent / 100); }
        function brightnessSet(percent: int): void { Brightness.set(percent / 100); }
    }

    //   qs -p ~/PluDE ipc call settings open
    //   qs -p ~/PluDE ipc call settings openPage monitors
    IpcHandler {
        target: "settings"

        function open(): void { SettingsApp.open(""); }
        function openPage(page: string): void { SettingsApp.open(page); }
        function toggle(): void { SettingsApp.toggle(); }
        function close(): void { SettingsApp.close(); }
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
