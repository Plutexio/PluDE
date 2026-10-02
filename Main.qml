import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common
import qs.PluAppDock
import qs.PluBar
import qs.PluClipboard
import qs.PluLauncher
import qs.PluScreenshot
import qs.PluSettings

// Właściwa powłoka, ładowana przez shell.qml tylko na Hyprlandzie.
Item {
    // Dock i launcher na jednym monitorze (Settings.dockScreen, domyślnie
    // automat jak w wyspie). Bez Variants: jeden dock, nie po jednym na ekran.
    Dock {}
    Launcher {}
    Bar {}
    Clipboard {}
    ShotToast {}

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

    //   qs -p ~/PluDE ipc call clipboard toggle
    IpcHandler {
        target: "clipboard"

        function toggle(): void { ClipboardService.toggle(); }
        function show(): void { ClipboardService.show(); }
        function hide(): void { ClipboardService.hide(); }
        function clear(): void { ClipboardService.clear(); }
    }

    //   qs -p ~/PluDE ipc call screenshot region
    //   qs -p ~/PluDE ipc call screenshot delayed screen 3
    IpcHandler {
        target: "screenshot"

        function region(): void { ScreenshotService.capture("region"); }
        function window(): void { ScreenshotService.capture("window"); }
        function screen(): void { ScreenshotService.capture("screen"); }
        function delayed(mode: string, seconds: int): void { ScreenshotService.delayed(mode, seconds); }
        // Akcja z powiadomienia o zrzucie w wyspie: edit / folder / delete.
        function act(action: string, path: string): void { ScreenshotService.act(action, path); }
        // Ostatni zrzut w edytorze (swappy).
        function edit(): void {
            if (ScreenshotService.last) ScreenshotService.edit(ScreenshotService.last.path, ScreenshotService.last.path);
        }
    }

    // Skróty globalne — klawisze przypisuje Hyprland (hyprland.lua):
    //   hl.bind(mainMod .. " + R", hl.dsp.global("quickshell:launcherToggle"))
    GlobalShortcut {
        appid: "quickshell"
        name: "launcherToggle"
        description: "Pokaż / ukryj launcher PluDE"

        onPressed: LauncherService.toggle()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "clipboardToggle"
        description: "Pokaż / ukryj historię schowka PluDE"

        onPressed: ClipboardService.toggle()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "screenshotRegion"
        description: "Zrzut zaznaczonego obszaru albo klikniętego okna"

        onPressed: ScreenshotService.capture("region")
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "screenshotScreen"
        description: "Zrzut całego ekranu"

        onPressed: ScreenshotService.capture("screen")
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "screenshotWindow"
        description: "Zrzut aktywnego okna"

        onPressed: ScreenshotService.capture("window")
    }
}
