import QtQuick
import Quickshell
import qs.Common

// Panel dysków pod kontrolką paska: dysk (nazwa, rozmiar, wysunięcie),
// pod nim jego woluminy (klik: zamontuj i otwórz). Okno i otwarcie jak
// w SliderPanel: xdg_popup z grabFocus, wyrasta z kontrolki (GrowBody).
PopupWindow {
    id: panel

    property int panelWidth: 300
    property int padding: 12
    property int diskRowHeight: 30
    property int volumeRowHeight: 46
    // Od tylu procent zajętości pasek woluminu robi się ostrzegawczy.
    property real fullWarn: 0.9

    color: "transparent"
    grabFocus: true
    visible: false

    // Okno szersze i wyższe od panelu o margines na cień (GrowBody).
    implicitWidth: grow.implicitWidth
    implicitHeight: grow.implicitHeight

    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.FlipY

    // Klik w kontrolkę dochodzi PO zamknięciu przez kompozytor (SliderPanel).
    property double closedAt: 0
    onVisibleChanged: if (!visible) closedAt = Date.now()

    function toggleAt(window, x, y) {
        if (visible) { visible = false; return; }
        if (Date.now() - closedAt < 250) return;
        // Zajętość sysfs nie zgłasza, więc świeży odczyt przy otwarciu.
        Drives.refresh();
        anchor.window = window;
        anchor.rect.x = Math.round(x);
        anchor.rect.y = Math.round(y);
        anchor.rect.width = 1;
        anchor.rect.height = 1;
        // Gdzie w oknie panelu wypada kontrolka: okno stoi środkiem pod
        // kotwicą, a przy krawędzi ekranu kompozytor je dosuwa (Slide).
        // Okno paska ma szerokość ekranu, więc jego x to x ekranu.
        const left = Math.max(0, Math.min(window.width - implicitWidth, x - implicitWidth / 2));
        originX = x - left;
        reveal = 0;
        visible = true;
        openAnim.restart();
    }

    // Ostatni dysk wyjęty → nie ma czego pokazywać.
    Connections {
        target: Drives
        function onPresentChanged() { if (!Drives.present) panel.visible = false; }
    }

    // Panel wyrasta z kontrolki (GrowBody): z pigułki pod nią na boki,
    // potem w dół, sprężyście. Zamknięcia nie animujemy — robi je kompozytor.
    property real reveal: 0
    property real originX: implicitWidth / 2
    NumberAnimation {
        id: openAnim
        target: panel; property: "reveal"; from: 0; to: 1
        duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.25
    }

    // Klik w przezroczysty margines na cień to klik obok panelu.
    mask: Region { item: grow.body }

    GrowBody {
        id: grow
        anchors.fill: parent
        reveal: panel.reveal
        originX: panel.originX
        contentWidth: panel.panelWidth
        contentHeight: column.implicitHeight + panel.padding * 2

        Column {
            id: column
            x: panel.padding
            y: panel.padding
            width: parent.width - panel.padding * 2
            spacing: 4

            Repeater {
                model: Drives.disks

                Column {
                    id: diskBlock
                    required property var modelData
                    required property int index
                    readonly property var disk: modelData
                    readonly property string action: Drives.busy[disk.path] || ""

                    width: parent.width

                    // Kreska między dyskami.
                    Rectangle {
                        visible: diskBlock.index > 0
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

                    // ---- dysk ----
                    Item {
                        width: parent.width
                        height: panel.diskRowHeight

                        Icon {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            kind: Drives.iconFor(diskBlock.disk)
                            size: 14
                            color: Theme.textDim
                        }

                        Text {
                            id: diskName
                            x: 30
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.width - x - diskSize.implicitWidth - ejectButton.width - 16)
                            text: diskBlock.disk.name
                            color: Theme.textDim
                            font.pixelSize: 12
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            id: diskSize
                            anchors.left: diskName.right
                            anchors.leftMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: Drives.size(diskBlock.disk.size)
                            color: Theme.textFaint
                            font.pixelSize: 11
                        }

                        // Wysunięcie: odmontuj wszystko i wyłącz zasilanie.
                        Rectangle {
                            id: ejectButton
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 26
                            radius: 13
                            visible: !diskBlock.disk.released
                            color: ejectMouse.pressed ? Theme.surfacePressed : ejectMouse.containsMouse ? Theme.surfaceRaised : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.quickMs } }

                            Icon {
                                anchors.centerIn: parent
                                kind: "eject"
                                size: 15
                                color: diskBlock.action === "eject" ? Theme.accent : Theme.text
                                opacity: diskBlock.action === "eject" ? 0.4 + 0.6 * pulse.value : 1
                            }

                            MouseArea {
                                id: ejectMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: diskBlock.action === ""
                                onClicked: Drives.eject(diskBlock.disk)
                            }
                        }
                    }

                    // ---- woluminy ----
                    Repeater {
                        model: diskBlock.disk.volumes

                        Rectangle {
                            id: vol
                            required property var modelData
                            readonly property var v: modelData
                            readonly property bool mounted: v.mount !== ""
                            readonly property bool mounting: Drives.busy[v.path] === "mount"
                            readonly property real usage: v.total > 0 ? v.used / v.total : 0

                            width: parent.width
                            height: panel.volumeRowHeight
                            radius: 10
                            color: volMouse.pressed ? Theme.surfacePressed : volMouse.containsMouse ? Theme.surfaceRaised : "transparent"
                            opacity: diskBlock.disk.released ? 0.55 : 1
                            Behavior on color { ColorAnimation { duration: Theme.quickMs } }

                            Icon {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                kind: vol.v.locked ? "lock" : "folder"
                                size: 16
                                color: vol.mounted ? Theme.accent : Theme.textDim
                                opacity: vol.mounting ? 0.4 + 0.6 * pulse.value : 1
                            }

                            Text {
                                id: volTitle
                                x: 32
                                y: 7
                                width: parent.width - x - volSide.implicitWidth - 18
                                text: vol.v.title
                                color: Theme.text
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }

                            // Po prawej: wolne miejsce albo rozmiar.
                            Text {
                                id: volSide
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.baseline: volTitle.baseline
                                text: vol.mounted && vol.v.total > 0 ? Drives.size(vol.v.avail) + " wolne"
                                    : Drives.size(vol.v.size)
                                color: Theme.textDim
                                font.pixelSize: 11
                                font.features: { "tnum": 1 }
                            }

                            // Druga linia: pasek zajętości (zamontowany) albo stan.
                            Rectangle {
                                visible: vol.mounted && vol.v.total > 0 && !vol.mounting
                                x: 32
                                y: 30
                                width: parent.width - x - 10
                                height: 4
                                radius: 2
                                color: Theme.surfacePressed

                                Rectangle {
                                    width: Math.max(height, parent.width * Math.min(1, vol.usage))
                                    height: parent.height
                                    radius: 2
                                    color: vol.usage >= panel.fullWarn ? Theme.warning : Theme.accent
                                }
                            }

                            Text {
                                visible: !vol.mounted || vol.v.total <= 0 || vol.mounting
                                x: 32
                                y: 25
                                width: parent.width - x - 10
                                text: diskBlock.disk.released ? "można bezpiecznie wyjąć"
                                    : vol.mounting ? "montowanie…"
                                    : diskBlock.action === "eject" ? "wysuwanie…"
                                    : vol.v.locked ? "zaszyfrowany · klik: odblokuj"
                                    : vol.mounted ? vol.v.fstype
                                    : "niezamontowany · " + vol.v.fstype
                                color: diskBlock.disk.released ? Theme.success
                                     : vol.mounting || diskBlock.action === "eject" ? Theme.accent
                                     : Theme.textFaint
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: volMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: diskBlock.action === "" && !vol.mounting && !diskBlock.disk.released
                                // Najpierw zamknięcie, potem akcja (PopupMenu).
                                onClicked: {
                                    const v = vol.v;
                                    panel.visible = false;
                                    Drives.open(v);
                                }
                            }
                        }
                    }

                    // Dysk bez systemu plików (czysty, nieznany format).
                    Text {
                        visible: diskBlock.disk.volumes.length === 0
                        x: 30
                        height: 24
                        verticalAlignment: Text.AlignVCenter
                        text: "brak systemu plików do zamontowania"
                        color: Theme.textFaint
                        font.pixelSize: 11
                    }
                }
            }

            // ---- błąd ostatniej akcji ----
            Text {
                visible: Drives.error !== ""
                x: 8
                width: parent.width - 16
                topPadding: 4
                text: Drives.error
                color: Theme.warning
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
        }
    }

    // Pulsowanie ikony w trakcie montowania i wysuwania.
    QtObject {
        id: pulse
        property real value: 1
    }
    SequentialAnimation {
        running: panel.visible && Drives.working
        loops: Animation.Infinite
        onRunningChanged: if (!running) pulse.value = 1
        NumberAnimation { target: pulse; property: "value"; to: 0; duration: 420; easing.type: Easing.InOutSine }
        NumberAnimation { target: pulse; property: "value"; to: 1; duration: 420; easing.type: Easing.InOutSine }
    }
}
