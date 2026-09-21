import QtQuick
import Quickshell

// Menu kontekstowe docka i launchera, także lista okien aplikacji.
// Osobne okno (xdg_popup), nie element w oknie docka: menu z kilkunastoma
// oknami jest wyższe niż zapas nad dockiem, a okno docka ma stałą wysokość
// (zmiana rozmiaru powierzchni layer-shella przy każdym otwarciu menu
// przestawiałaby dock).
//
// grabFocus: klik poza menu zamyka je sam kompozytor.
PopupWindow {
    id: menu

    // Wpis: { text, icon?, checked?, danger?, enabled?, run: function }
    //    albo { header: "…" }  albo { separator: true }
    property var entries: []

    property int menuWidth: 240
    property int rowHeight: 30
    property int padding: 6

    color: "transparent"
    grabFocus: true
    visible: false

    implicitWidth: menuWidth
    implicitHeight: column.implicitHeight + padding * 2

    // Menu nad punktem (x, y) okna, wyśrodkowane w poziomie.
    // Slide: przy krawędzi ekranu kompozytor przesuwa menu, zamiast je ucinać.
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.FlipY

    function openAt(window, x, y, list) {
        entries = list;
        anchor.window = window;
        anchor.rect.x = Math.round(x);
        anchor.rect.y = Math.round(y);
        anchor.rect.width = 1;
        anchor.rect.height = 1;
        visible = true;
    }

    function close() { visible = false; }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        Column {
            id: column
            x: menu.padding
            y: menu.padding
            width: parent.width - menu.padding * 2

            Repeater {
                model: menu.entries

                Item {
                    id: row

                    required property var modelData
                    readonly property bool isSeparator: !!modelData.separator
                    readonly property bool isHeader: modelData.header !== undefined
                    readonly property bool enabled_: modelData.enabled !== false

                    width: column.width
                    height: isSeparator ? 9 : (isHeader ? 26 : menu.rowHeight)

                    Rectangle {
                        visible: row.isSeparator
                        anchors.centerIn: parent
                        width: parent.width - 12
                        height: 1
                        color: Theme.border
                    }

                    Text {
                        visible: row.isHeader
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 20
                        text: row.isHeader ? row.modelData.header : ""
                        color: Theme.textDim
                        font.pixelSize: 11
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: !row.isSeparator && !row.isHeader
                        anchors.fill: parent
                        radius: 10
                        color: rowMouse.containsMouse && row.enabled_
                               ? (row.modelData.danger ? Qt.rgba(0.9, 0.28, 0.3, 0.2) : Theme.hoverStrong)
                               : "transparent"

                        // Kropka zaznaczenia (aktywne okno) albo ikona wpisu.
                        Rectangle {
                            visible: !!row.modelData.checked
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.accent
                        }

                        Image {
                            visible: !row.modelData.checked && !!row.modelData.icon
                            x: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            height: 16
                            source: row.modelData.icon || ""
                            sourceSize: Qt.size(16, 16)
                            asynchronous: false
                        }

                        Text {
                            x: 28
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - 10
                            text: row.modelData.text || ""
                            color: !row.enabled_ ? Theme.textFaint
                                   : (row.modelData.danger ? Theme.danger : Theme.text)
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: row.enabled_
                            onClicked: {
                                // Najpierw zamknięcie, potem akcja: akcja potrafi
                                // zmienić entries (okno znika → Repeater niszczy
                                // ten delegat w trakcie jego własnego onClicked —
                                // ta sama pułapka co w historii wyspy).
                                const run = row.modelData.run;
                                menu.close();
                                if (run) run();
                            }
                        }
                    }
                }
            }
        }
    }
}
