import QtQuick
import Quickshell
import qs.Common

// Strona „Ogólne”: to, co wcześniej trzeba było wpisać ręcznie do
// settings.json. Każda zmiana zapisuje się od razu i wchodzi na żywo.
Column {
    id: page

    spacing: 22

    // ---- monitor docka ----

    // Automat pokazuje, który ekran wybrał, żeby „Automatycznie” nie
    // było zagadką. Zapisany monitor, którego teraz nie ma (druga maszyna,
    // odłączony kabel), zostaje na liście — inaczej lista pokazałaby „—”.
    readonly property var screenChoices: {
        const auto = Settings.pickScreen("");
        const out = [{ value: "", label: "Automatycznie" + (auto ? " (" + auto.name + ")" : "") }];
        const names = [];
        MonitorService.monitors.forEach(m => {
            if (m.disabled) return;
            names.push(m.name);
            out.push({ value: m.name, label: m.description !== "" ? m.name + " · " + m.description : m.name });
        });
        if (Settings.dockScreen !== "" && names.indexOf(Settings.dockScreen) < 0)
            out.push({ value: Settings.dockScreen, label: Settings.dockScreen + " (odłączony)" });
        return out;
    }

    SettingsSection {
        width: page.width
        title: "Dock, launcher i pasek"

        SettingsRow {
            title: "Monitor"
            description: "Ekran, na którym stoją dock, launcher i pasek. Automatycznie: monitor w punkcie (0,0)."

            SettingsChoice {
                width: 260
                model: page.screenChoices
                value: Settings.dockScreen
                onPicked: v => Settings.set("dockScreen", v)
            }
        }

        SettingsRow {
            title: "Chowaj z wyspą"
            description: "Ukrycie wyspy skrótem chowa też dock i pasek."

            SettingsSwitch {
                checked: Settings.hideWithIsland
                onToggled: Settings.set("hideWithIsland", !Settings.hideWithIsland)
            }
        }

        SettingsRow {
            title: "Miejsce na pasek"
            description: "Okna zaczynają się pod paskiem. Wyłączone: pasek unosi się nad oknami jak wyspa."

            SettingsSwitch {
                checked: Settings.barReserve
                onToggled: Settings.set("barReserve", !Settings.barReserve)
            }
        }
    }

    SettingsSection {
        width: page.width
        title: "Aplikacje"

        SettingsRow {
            title: "Terminal"
            description: "Dla aplikacji z Terminal=true (htop, btop). Uruchamiany z -e."

            SettingsField {
                width: 260
                value: Settings.terminal
                placeholder: "kitty"
                onCommitted: t => Settings.set("terminal", t.trim())
            }
        }

        SettingsRow {
            title: "Katalog wyspy"
            description: "Konfiguracja PluDynamicIsland. Pod nią idą polecenia do wyspy (nakładki, powiadomienia)."

            SettingsField {
                width: 260
                // Surowa wartość z pliku (z ~), nie rozwinięta ścieżka.
                value: Settings.islandPathRaw
                placeholder: "~/PluDynamicIsland"
                onCommitted: t => Settings.set("islandPath", t.trim())
            }
        }
    }

    Text {
        x: 4
        width: page.width - 8
        text: "Zapis od razu do ~/.config/plude/settings.json. Plik można dalej edytować ręcznie."
        color: Theme.textFaint
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
}
