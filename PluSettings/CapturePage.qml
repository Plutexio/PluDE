import QtQuick
import Quickshell
import qs.Common
import qs.PluClipboard
import qs.PluScreenshot

// Strona „Schowek i zrzuty”: ustawienia historii schowka i zrzutów ekranu
// (settings.json). Skróty klawiszowe są w hyprland.lua, tutaj tylko je widać.
Column {
    id: page

    spacing: 22

    // Narzędzia mogły zostać doinstalowane od startu powłoki.
    Component.onCompleted: ScreenshotService.checkTools()

    // Plakietka skrótu (DESIGN.md: zaokrąglona 6, litera pogrubiona).
    component KeyCaps: Row {
        id: keys
        property var keys: []
        spacing: 4

        Repeater {
            model: keys.keys

            Rectangle {
                required property string modelData
                width: Math.max(24, keyLabel.implicitWidth + 12)
                height: 22
                radius: 6
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                Text {
                    id: keyLabel
                    anchors.centerIn: parent
                    text: parent.modelData
                    color: Theme.text
                    font.pixelSize: 11
                    font.bold: true
                }
            }
        }
    }

    SettingsSection {
        width: page.width
        title: "Schowek"

        SettingsRow {
            title: "Historia schowka"
            description: "Tekst i obrazy, które kopiujesz. Hasła oznaczone przez menedżer haseł nie są zapamiętywane."

            KeyCaps { keys: ["Super", "Shift", "V"] }
        }

        SettingsRow {
            title: "Wklejaj po wybraniu"
            description: "Wybrany wpis trafia od razu do okna, z którego otwarto schowek. Wyłączone: tylko do schowka."

            SettingsSwitch {
                checked: Settings.clipboardPaste
                onToggled: Settings.set("clipboardPaste", !Settings.clipboardPaste)
            }
        }

        SettingsRow {
            title: "Liczba wpisów"
            description: "Starsze wypadają z historii. Przypięte się nie liczą i zostają."

            SettingsChoice {
                width: 120
                model: [25, 50, 100, 200, 500].map(n => ({ value: n, label: String(n) }))
                value: Settings.clipboardMax
                onPicked: v => Settings.set("clipboardMax", v)
            }
        }

        SettingsRow {
            readonly property int count: ClipboardService.unpinnedCount
            readonly property int pinned: ClipboardService.items.length - count

            title: "Wyczyść historię"
            description: count + " " + ClipboardService.plural(count, "wpis", "wpisy", "wpisów")
                + (pinned > 0 ? " i " + pinned + " " + ClipboardService.plural(pinned, "przypięty, który zostanie", "przypięte, które zostaną", "przypiętych, które zostaną") : "")
                + "."

            SettingsButton {
                text: "Wyczyść"
                tint: Theme.danger
                enabled: ClipboardService.unpinnedCount > 0
                onClicked: ClipboardService.clear()
            }
        }
    }

    SettingsSection {
        width: page.width
        title: "Zrzuty ekranu"

        SettingsRow {
            title: "Obszar albo okno"
            description: "Przeciągnij, żeby zaznaczyć obszar. Klik w okno albo w pusty ekran bierze je w całości."

            KeyCaps { keys: ["Print"] }
        }

        SettingsRow {
            title: "Cały ekran"
            description: "Monitor, na którym jest fokus."

            KeyCaps { keys: ["Shift", "Print"] }
        }

        SettingsRow {
            title: "Aktywne okno"

            KeyCaps { keys: ["Super", "Print"] }
        }

        SettingsRow {
            title: "Katalog"
            description: "Tu zapisują się zrzuty."

            SettingsField {
                width: 260
                // Surowa wartość z pliku (z ~), nie rozwinięta ścieżka.
                value: Settings.screenshotDirRaw
                placeholder: "~/Pictures/Screenshots"
                onCommitted: t => { if (t.trim() !== "") Settings.set("screenshotDir", t.trim()); }
            }
        }

        SettingsRow {
            title: "Kopiuj do schowka"
            description: "Zrzut od razu da się wkleić i trafia do historii schowka."

            SettingsSwitch {
                checked: Settings.screenshotCopy
                onToggled: Settings.set("screenshotCopy", !Settings.screenshotCopy)
            }
        }

        SettingsRow {
            title: "Od razu edytor"
            description: "Po zrzucie otwiera się swappy. Wyłączone: podgląd w rogu ekranu, edytor po kliknięciu."

            SettingsSwitch {
                checked: Settings.screenshotEdit
                onToggled: Settings.set("screenshotEdit", !Settings.screenshotEdit)
            }
        }

        SettingsRow {
            title: "Kursor na zrzucie"

            SettingsSwitch {
                checked: Settings.screenshotCursor
                onToggled: Settings.set("screenshotCursor", !Settings.screenshotCursor)
            }
        }
    }

    // Stan narzędzi: bez nich skróty nie robią nic poza komunikatem o błędzie.
    Row {
        x: 4
        spacing: 8

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            radius: 4
            color: ScreenshotService.missing.length === 0 ? Theme.success : Theme.danger
        }

        Text {
            width: page.width - 24
            text: ScreenshotService.missing.length === 0
                ? "grim, slurp, swappy i wl-clipboard są zainstalowane."
                : "Brakuje: " + ScreenshotService.missing.join(", ") + ". Zainstaluj: sudo pacman -S grim slurp swappy wl-clipboard"
            color: ScreenshotService.missing.length === 0 ? Theme.textFaint : Theme.text
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
}
