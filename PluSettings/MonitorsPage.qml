import QtQuick
import qs.Common

// Strona „Monitory”: układ do przeciągania i ustawienia zaznaczonego
// monitora. Wszystko zmienia szkic (MonitorDraft); do Hyprlanda idzie
// dopiero „Zastosuj”, a potem okno potwierdzenia (MonitorConfirm w oknie).
Column {
    id: page

    spacing: 22
    enabled: !MonitorService.pending

    MonitorDraft { id: plan }

    readonly property var e: plan.current
    readonly property bool several: plan.items.length > 1

    property string error: ""

    Connections {
        target: MonitorService
        function onFailed(message) { page.error = message; }
    }

    // ---- listy wyboru ----

    readonly property var resolutionChoices: {
        if (!e) return [];
        const seen = {};
        const out = [];
        e.modes.slice().sort((a, b) => b.width * b.height - a.width * a.height).forEach(m => {
            const key = m.width + "x" + m.height;
            if (seen[key]) return;
            seen[key] = true;
            out.push({ value: key, label: m.width + " × " + m.height });
        });
        return out;
    }

    function refreshLabel(r) { return (+r.toFixed(2)) + " Hz"; }

    readonly property var refreshChoices: {
        if (!e) return [];
        return e.modes.filter(m => m.width === e.width && m.height === e.height)
            .map(m => m.refresh)
            .sort((a, b) => b - a)
            .map(r => ({ value: r, label: refreshLabel(r) }));
    }

    // Tylko skale, przy których rozmiar logiczny wychodzi w całych pikselach
    // (inne Hyprland i tak by poprawił). Bieżąca, nawet nietypowa, zostaje.
    readonly property var scaleValues: {
        if (!e) return [];
        const out = MonitorService.validScales(e.width, e.height, 1, 3);
        if (!out.some(s => Math.abs(s - e.scale) < 1e-3)) out.push(e.scale);
        return out.sort((a, b) => a - b);
    }
    readonly property var scaleChoices: scaleValues.map(s => ({ value: s, label: Math.round(s * 100) + "%" }))
    // Ta sama wartość z listy (1.3333333), a nie z Hyprlanda (1.3333334) —
    // inaczej lista nie rozpozna bieżącej skali.
    readonly property var scaleValue: e ? (scaleValues.find(s => Math.abs(s - e.scale) < 1e-3) ?? e.scale) : null

    readonly property var transformChoices: {
        const out = [
            { value: 0, label: "Bez obrotu" },
            { value: 1, label: "90°" },
            { value: 2, label: "180°" },
            { value: 3, label: "270°" }
        ];
        // Odbicie (4–7) da się ustawić tylko ręcznie; nie gubimy go.
        if (e && e.transform >= 4) out.push({ value: e.transform, label: "Odbity" });
        return out;
    }

    readonly property var mirrorChoices: {
        if (!e) return [];
        const out = [{ value: "", label: "Nie" }];
        plan.items.forEach(o => {
            if (o.name !== e.name && !o.disabled && o.mirror === "")
                out.push({ value: o.name, label: "Klon " + o.name });
        });
        return out;
    }

    // ---------------------------------------------------------------
    // Układ
    // ---------------------------------------------------------------

    SettingsSection {
        width: page.width
        title: "Układ"

        Item {
            width: parent.width
            height: 250

            MonitorCanvas {
                anchors.fill: parent
                anchors.margins: 6
                draft: plan
            }
        }

        // Wybór monitora także tutaj: wyłączonych nie ma na płótnie.
        Item {
            width: parent.width
            height: chips.height + 28

            Rectangle {
                x: 16
                width: parent.width - 32
                height: 1
                color: Theme.border
            }

            Flow {
                id: chips
                x: 16
                y: 14
                width: parent.width - 32
                spacing: 6

                Repeater {
                    model: plan.items.length

                    Rectangle {
                        id: chip

                        required property int index
                        readonly property var m: plan.items[index] ?? null
                        readonly property bool current: m !== null && plan.selected === m.name

                        width: chipText.implicitWidth + 24
                        height: 28
                        radius: 14
                        color: current ? Qt.tint(Theme.surfaceRaised, Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2))
                            : chipMouse.containsMouse ? Theme.surface : Theme.surfaceRaised
                        border.width: 1
                        border.color: current ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)

                        Behavior on color { ColorAnimation { duration: Theme.quickMs } }

                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.m ? chip.m.name + (chip.m.disabled ? " (wyłączony)" : "") : ""
                            color: chip.m && chip.m.disabled ? Theme.textDim : Theme.text
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: plan.selected = chip.m.name
                        }
                    }
                }
            }
        }
    }

    // Co jest nie tak z układem, albo podpowiedź, jak go zmienić.
    Text {
        x: 4
        width: page.width - 8
        wrapMode: Text.Wrap
        font.pixelSize: 12
        color: plan.problems.overlap.length > 0 ? Theme.danger
            : plan.problems.detached ? Theme.warning : Theme.textFaint
        text: plan.problems.overlap.length > 0
                ? "Monitory nachodzą na siebie: " + plan.problems.overlap.join(", ") + ". Rozsuń je, żeby zastosować."
            : plan.problems.detached
                ? "Nie wszystkie monitory stykają się krawędzią — kursor nie przejdzie między nimi."
            : several ? "Przeciągnij monitor, żeby zmienić jego położenie. Krawędzie przyciągają się do sąsiadów."
            : ""
        visible: text !== ""
    }

    // ---------------------------------------------------------------
    // Zaznaczony monitor
    // ---------------------------------------------------------------

    SettingsSection {
        width: page.width
        visible: page.e !== null
        title: page.e ? page.e.name + (page.e.description !== "" ? " · " + page.e.description : "") : ""

        SettingsRow {
            visible: page.several
            title: "Włączony"
            description: "Wyłączony monitor nie dostaje obrazu ani obszarów roboczych."

            SettingsSwitch {
                checked: page.e !== null && !page.e.disabled
                // Ostatniego włączonego nie da się wyłączyć.
                enabled: page.e !== null && (page.e.disabled || plan.items.filter(o => !o.disabled).length > 1)
                onToggled: plan.setEnabled(page.e.name, page.e.disabled)
            }
        }

        SettingsRow {
            title: "Rozdzielczość"
            enabled: page.e !== null && !page.e.disabled

            SettingsChoice {
                width: 220
                model: page.resolutionChoices
                value: page.e ? page.e.width + "x" + page.e.height : null
                onPicked: v => {
                    const p = v.split("x");
                    plan.setResolution(page.e.name, +p[0], +p[1]);
                }
            }
        }

        SettingsRow {
            title: "Odświeżanie"
            enabled: page.e !== null && !page.e.disabled

            SettingsChoice {
                width: 220
                model: page.refreshChoices
                value: page.e ? page.e.refresh : null
                onPicked: v => plan.setRefresh(page.e.name, v)
            }
        }

        SettingsRow {
            title: "Skala"
            description: "Tylko wartości, przy których obraz wychodzi w całych pikselach."
            enabled: page.e !== null && !page.e.disabled

            SettingsChoice {
                width: 220
                model: page.scaleChoices
                value: page.scaleValue
                onPicked: v => plan.setScale(page.e.name, v)
            }
        }

        SettingsRow {
            title: "Obrót"
            enabled: page.e !== null && !page.e.disabled

            SettingsChoice {
                width: 220
                model: page.transformChoices
                value: page.e ? page.e.transform : null
                onPicked: v => plan.setTransform(page.e.name, v)
            }
        }

        SettingsRow {
            visible: page.several
            title: "Klon"
            description: "Ten sam obraz co na innym monitorze."
            enabled: page.e !== null && !page.e.disabled

            SettingsChoice {
                width: 220
                model: page.mirrorChoices
                value: page.e ? page.e.mirror : null
                onPicked: v => plan.setMirror(page.e.name, v)
            }
        }
    }

    // ---------------------------------------------------------------
    // Zastosowanie
    // ---------------------------------------------------------------

    Item {
        width: page.width
        height: buttons.height

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: buttons.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.Wrap
            font.pixelSize: 12
            color: page.error !== "" ? Theme.danger : Theme.textFaint
            text: page.error !== "" ? "Hyprland odrzucił zmianę: " + page.error
                : plan.dirty ? "Po zastosowaniu masz " + MonitorService.confirmSeconds
                                + " s na potwierdzenie, potem wraca poprzedni układ."
                : ""
        }

        Row {
            id: buttons
            anchors.right: parent.right
            spacing: 8

            SettingsButton {
                text: "Przywróć"
                enabled: plan.dirty
                onClicked: {
                    page.error = "";
                    plan.reset();
                }
            }

            SettingsButton {
                text: "Zastosuj"
                primary: true
                enabled: plan.dirty && plan.valid
                onClicked: {
                    page.error = "";
                    plan.apply();
                }
            }
        }
    }

    // Czy układ przeżyje restart: zapisuje go dopiero „Zachowaj”.
    Text {
        x: 4
        width: page.width - 8
        wrapMode: Text.Wrap
        font.pixelSize: 11
        color: Theme.textFaint
        text: {
            const connected = MonitorService.monitors;
            const saved = connected.filter(m => MonitorService.rules[m.output] !== undefined).length;
            return saved === connected.length && saved > 0
                ? "Układ zapisany w ~/.config/hypr/plude-monitors.lua — Hyprland ustawia go sam przy starcie."
                : "Bez zapisanego układu Hyprland ustawia monitory sam (preferred, auto). „Zachowaj” po zmianie zapisze go na stałe.";
        }
    }
}
