pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ---------------------------------------------------------------
// Jasność ekranu (podświetlenie laptopa).
//
// Odczyt z /sys/class/backlight/<urządzenie>/brightness, zapis przez
// logind (Session.SetBrightness): plik w sysfs należy do roota, a logind
// pozwala zmieniać jasność aktywnej sesji bez uprawnień (sprawdzone
// busctl-em). brightnessctl, którego używały klawisze w hyprland.lua, nie
// jest zainstalowany.
//
// sysfs nie zgłasza zmian przez inotify, więc odczyt co pollMs. Zmiany
// z paska widać od razu, bo wartość ustawiamy u siebie przed zapisem.
// ---------------------------------------------------------------
Singleton {
    id: root

    property int pollMs: 1500
    // Najciemniej, ile da się ustawić suwakiem albo kółkiem. Zero to na
    // wielu matrycach całkiem czarny ekran, z którego nie widać paska.
    property real minimum: 0.01
    property real step: 0.05
    // Przeciąganie suwaka daje dziesiątki zmian na sekundę; do logind idzie
    // najwyżej jedna na tyle ms (ostatnia wartość wygrywa).
    property int writeIntervalMs: 40

    readonly property bool available: device !== "" && max > 0
    // 0–1, liniowo względem max_brightness.
    readonly property real value: max > 0 ? current / max : 0

    property string device: ""
    property int max: 0
    property int current: 0

    function set(v) {
        if (!available) return;
        const c = Math.max(minimum, Math.min(1, v));
        root.current = Math.round(c * max);
        pending = root.current;
        if (!writeTimer.running) writeTimer.start();
    }

    // Zaokrąglenie do pełnego kroku, jak głośność w wyspie: inaczej ten sam
    // ruch kółkiem dwa razy daje inny wynik.
    function stepBy(delta) {
        set(Math.round((value + delta) * 100) / 100);
    }

    property int pending: -1

    Timer {
        id: writeTimer
        interval: root.writeIntervalMs
        onTriggered: {
            if (root.pending < 0) return;
            Quickshell.execDetached(["busctl", "call", "org.freedesktop.login1",
                "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session",
                "SetBrightness", "ssu", "backlight", root.device, String(root.pending)]);
            root.pending = -1;
        }
    }

    // ---- odczyt ----

    // Pierwsze urządzenie z /sys/class/backlight. Na laptopie jest jedno
    // (intel_backlight); na desktopie nie ma żadnego i kontrolka znika.
    Process {
        running: true
        command: ["sh", "-c", "ls /sys/class/backlight | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: root.device = text.trim()
        }
    }

    FileView {
        id: maxFile
        path: root.device !== "" ? "/sys/class/backlight/" + root.device + "/max_brightness" : ""
        onLoaded: root.max = parseInt(text()) || 0
    }

    FileView {
        id: curFile
        path: root.device !== "" ? "/sys/class/backlight/" + root.device + "/brightness" : ""
        // Zapis w toku: odczyt sprzed niego cofnąłby suwak pod palcem.
        onLoaded: if (!writeTimer.running && root.pending < 0) root.current = parseInt(text()) || 0
    }

    Timer {
        interval: root.pollMs
        running: root.device !== ""
        repeat: true
        onTriggered: curFile.reload()
    }
}
