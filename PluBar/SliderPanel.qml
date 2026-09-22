import QtQuick
import Quickshell
import qs.Common

// Panel pod kontrolką paska: nagłówek z ikoną, suwak i opcjonalna lista
// (wyjścia dźwięku). Osobne okno (xdg_popup) jak PopupMenu — okno paska
// ma stałą wysokość, a lista wyjść nie ma się w nim gdzie zmieścić.
//
// grabFocus: klik obok zamyka panel (robi to kompozytor, bez animacji).
PopupWindow {
    id: panel

    property string title: ""
    property string icon: ""
    property color iconColor: Theme.text
    property real value: 0          // 0–1, powiązanie z właścicielem
    property real step: 0.05
    // { text, icon?, checked?, run } albo { header } — jak w PopupMenu.
    property var entries: []

    property int panelWidth: 280
    property int padding: 12
    property int sliderHeight: 26

    signal moved(real v)
    signal iconClicked()

    color: "transparent"
    grabFocus: true
    visible: false

    implicitWidth: panelWidth
    // Zapas na odbicie skali przy otwarciu, żeby nie wyjść poza okno.
    implicitHeight: body.implicitHeight + 8

    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.FlipY

    // Czas zamknięcia: klik w kontrolkę, która panel otworzyła, dochodzi
    // PO zamknięciu przez kompozytor (klik obok). Bez tego ten sam klik
    // otwierałby panel z powrotem.
    property double closedAt: 0
    onVisibleChanged: if (!visible) closedAt = Date.now()

    function toggleAt(window, x, y) {
        if (visible) { visible = false; return; }
        if (Date.now() - closedAt < 250) return;
        anchor.window = window;
        anchor.rect.x = Math.round(x);
        anchor.rect.y = Math.round(y);
        anchor.rect.width = 1;
        anchor.rect.height = 1;
        reveal = 0;
        visible = true;
        openAnim.restart();
    }

    // Otwarcie jak panel launchera, tylko mniejsze: skala z 0,92 i kilka px
    // wyżej, sprężyście. Zamknięcia nie animujemy — robi je kompozytor.
    property real reveal: 0
    NumberAnimation {
        id: openAnim
        target: panel; property: "reveal"; from: 0; to: 1
        duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.1
    }

    Rectangle {
        id: body
        width: panel.panelWidth
        implicitHeight: column.implicitHeight + panel.padding * 2
        height: implicitHeight
        radius: 16
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        transformOrigin: Item.Top
        scale: 0.92 + 0.08 * panel.reveal
        y: -10 * (1 - panel.reveal)
        opacity: Math.min(1, panel.reveal * 1.6)

        Column {
            id: column
            x: panel.padding
            y: panel.padding
            width: parent.width - panel.padding * 2
            spacing: 10

            // ---- nagłówek ----
            Item {
                width: parent.width
                height: 22

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.title
                    color: Theme.textDim
                    font.pixelSize: 12
                    font.bold: true
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(panel.value * 100) + "%"
                    color: Theme.text
                    font.pixelSize: 12
                    font.bold: true
                    font.features: { "tnum": 1 }
                }
            }

            // ---- suwak ----
            Row {
                width: parent.width
                spacing: 8

                // Ikona jest przyciskiem (wyciszenie przy głośności).
                Rectangle {
                    width: panel.sliderHeight
                    height: panel.sliderHeight
                    radius: height / 2
                    color: iconMouse.pressed ? "#2a2a2c" : iconMouse.containsMouse ? Theme.surfaceRaised : "transparent"

                    Icon {
                        anchors.centerIn: parent
                        kind: panel.icon
                        size: 16
                        color: panel.iconColor
                    }

                    MouseArea {
                        id: iconMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: panel.iconClicked()
                    }
                }

                Rectangle {
                    id: track
                    width: parent.width - panel.sliderHeight - 8
                    height: panel.sliderHeight
                    radius: height / 2
                    color: Theme.surfaceRaised
                    border.width: 1
                    border.color: Theme.border

                    // Wypełnienie nie schodzi poniżej koła, żeby przy 0% było
                    // widać, gdzie złapać. Ta sama skala co pick(): środek
                    // gałki stoi dokładnie pod kursorem.
                    Rectangle {
                        width: height + (parent.width - height) * Math.max(0, Math.min(1, panel.value))
                        height: parent.height
                        radius: height / 2
                        color: Theme.accent

                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.height - 8
                            height: width
                            radius: width / 2
                            color: Theme.text
                            scale: sliderMouse.pressed ? 1.12 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.OutBack } }
                        }
                    }

                    MouseArea {
                        id: sliderMouse
                        anchors.fill: parent
                        preventStealing: true

                        function pick(x) {
                            // Środek gałki przy x, więc skraje to połowa wysokości.
                            const r = track.height / 2;
                            panel.moved(Math.max(0, Math.min(1, (x - r) / (track.width - 2 * r))));
                        }
                        onPressed: event => pick(event.x)
                        onPositionChanged: event => { if (pressed) pick(event.x); }

                        property real acc: 0
                        onWheel: event => {
                            acc += event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
                            const n = Math.trunc(acc / 120);
                            if (n !== 0) {
                                acc -= n * 120;
                                panel.moved(Math.max(0, Math.min(1, Math.round((panel.value + n * panel.step) * 100) / 100)));
                            }
                        }
                    }
                }
            }

            // ---- lista ----
            Column {
                visible: panel.entries.length > 0
                width: parent.width

                Rectangle {
                    width: parent.width
                    height: 9
                    color: "transparent"
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 8
                        height: 1
                        color: Theme.border
                    }
                }

                Repeater {
                    model: panel.entries

                    Item {
                        id: row
                        required property var modelData
                        readonly property bool isHeader: modelData.header !== undefined

                        width: parent.width
                        height: isHeader ? 26 : 30

                        Text {
                            visible: row.isHeader
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.isHeader ? row.modelData.header : ""
                            color: Theme.textDim
                            font.pixelSize: 11
                            font.bold: true
                        }

                        Rectangle {
                            visible: !row.isHeader
                            anchors.fill: parent
                            radius: 10
                            color: rowMouse.containsMouse ? Theme.surfaceRaised : "transparent"

                            Icon {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                kind: row.modelData.icon || ""
                                size: 14
                                color: row.modelData.checked ? Theme.accent : Theme.textDim
                            }

                            Text {
                                x: 30
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - 24
                                text: row.modelData.text || ""
                                color: Theme.text
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                visible: !!row.modelData.checked
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: Theme.accent
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                // Akcja zmienia entries (inne wyjście zaznaczone) —
                                // bierzemy ją do zmiennej, zanim Repeater
                                // przebuduje delegaty (pułapka z historii wyspy).
                                onClicked: {
                                    const run = row.modelData.run;
                                    if (run) run();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
