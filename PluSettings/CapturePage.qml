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

    // Nazwy najczęstszych języków tesseracta; reszta pokazuje się kodem.
    readonly property var languageNames: ({
        pol: "Polski", eng: "Angielski", deu: "Niemiecki", fra: "Francuski",
        spa: "Hiszpański", ita: "Włoski", por: "Portugalski", nld: "Niderlandzki",
        ces: "Czeski", slk: "Słowacki", ukr: "Ukraiński", rus: "Rosyjski",
        bel: "Białoruski", lit: "Litewski", lav: "Łotewski", est: "Estoński",
        swe: "Szwedzki", nor: "Norweski", dan: "Duński", fin: "Fiński",
        hun: "Węgierski", ron: "Rumuński", bul: "Bułgarski", hrv: "Chorwacki",
        srp: "Serbski", slv: "Słoweński", ell: "Grecki", tur: "Turecki",
        jpn: "Japoński", kor: "Koreański", chi_sim: "Chiński uproszczony",
        chi_tra: "Chiński tradycyjny", ara: "Arabski", heb: "Hebrajski"
    })

    // Włączenie dopisuje język na końcu (pierwszy zostaje główny), a
    // wyłączenie ostatniego nie przechodzi: tesseract potrzebuje choć jednego.
    function toggleLanguage(code) {
        const current = ScreenshotService.ocrLanguages;
        const next = current.indexOf(code) >= 0 ? current.filter(l => l !== code) : current.concat([code]);
        if (next.length > 0) Settings.set("ocrLanguages", next.join("+"));
    }

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

    SettingsSection {
        width: page.width
        title: "Tekst ze zrzutu"

        SettingsRow {
            title: "Kopiuj tekst z obszaru"
            description: ScreenshotService.ocrMissing
                ? "Wymaga programu tesseract: sudo pacman -S tesseract tesseract-data-pol tesseract-data-eng"
                : "Zaznacz obszar albo kliknij okno. Rozpoznany tekst trafia do schowka, obraz nie jest zapisywany."

            KeyCaps { keys: ["Super", "Shift", "T"] }
        }

        Repeater {
            model: ScreenshotService.ocrMissing ? [] : ScreenshotService.ocrInstalled

            SettingsRow {
                id: languageRow
                required property string modelData
                readonly property bool on: ScreenshotService.ocrLanguages.indexOf(modelData) >= 0

                title: page.languageNames[modelData] ?? modelData
                description: on && ScreenshotService.ocrLanguages[0] === modelData && ScreenshotService.ocrLanguages.length > 1
                    ? "Główny język rozpoznawania." : ""

                SettingsSwitch {
                    checked: languageRow.on
                    // Ostatniego języka nie da się wyłączyć.
                    enabled: !(checked && ScreenshotService.ocrLanguages.length === 1)
                    onToggled: page.toggleLanguage(languageRow.modelData)
                }
            }
        }

        SettingsRow {
            visible: !ScreenshotService.ocrMissing
            title: "Inne języki"
            description: "Doinstaluj paczkę tesseract-data-<kod>, np. tesseract-data-deu, i otwórz tę stronę ponownie."
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
