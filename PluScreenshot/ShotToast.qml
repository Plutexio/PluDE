import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common

// Podgląd zrzutu w prawym dolnym rogu: miniatura i trzy akcje (edytuj,
// pokaż w katalogu, usuń). Znika sam po hideMs, najechanie go zatrzymuje.
// Zastępstwo za wyspę: przy żywej wyspie zrzut i błąd zgłasza ona
// (ScreenshotService.viaIsland), a to okno pokazuje tylko odliczanie
// przed zrzutem z opóźnieniem.
PanelWindow {
    id: root

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    property int cardWidth: 280
    property int thumbHeight: 150
    property int padding: 10
    property int edgeMargin: 16
    property int buttonSize: 30
    property int hideMs: 6000
    property int errorHideMs: 9000

    // ---------------------------------------------------------------
    // Okno
    // ---------------------------------------------------------------

    screen: ScreenshotService.screen ?? Settings.screen

    anchors {
        bottom: true
        right: true
    }

    // Stały rozmiar z zapasem na przestrzał sprężyny; klikalna jest tylko karta.
    implicitWidth: cardWidth + 2 * edgeMargin
    implicitHeight: thumbHeight + buttonSize + 4 * padding + 2 * edgeMargin
    mask: Region { item: card }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "plude-shot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // "shot" (miniatura), "error" albo "countdown".
    property string view: "shot"
    property string path: ""
    property string message: ""
    property bool copied: false

    property bool shown: false
    onShownChanged: ScreenshotService.toastShown = shown

    // Wejście sprężyste z prawej, wyjście krótkie.
    property real reveal: 0
    NumberAnimation {
        id: revealIn
        target: root; property: "reveal"; to: 1
        duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot
    }
    NumberAnimation {
        id: revealOut
        target: root; property: "reveal"; to: 0
        duration: 170; easing.type: Easing.InCubic
    }

    visible: shown || reveal > 0

    function show(kind) {
        view = kind;
        shown = true;
        revealOut.stop();
        revealIn.start();
        hideTimer.restart();
    }

    function hide() {
        shown = false;
        revealIn.stop();
        revealOut.start();
    }

    Connections {
        target: ScreenshotService

        // Przed zrzutem znikamy od razu, bez animacji: mamy nie być na zrzucie.
        function onStarting() {
            revealIn.stop();
            revealOut.stop();
            root.shown = false;
            root.reveal = 0;
        }

        function onCaptured(path) {
            root.path = path;
            root.copied = ScreenshotService.last ? ScreenshotService.last.copied : false;
            root.show("shot");
        }

        function onFailed(reason) {
            root.message = reason;
            root.show("error");
        }

        function onCountdownChanged() {
            if (ScreenshotService.countdown > 0 && !(root.shown && root.view === "countdown")) root.show("countdown");
        }
    }

    // Najechanie liczone z karty, miniatury i każdego przycisku osobno:
    // MouseArea na wierzchu zabiera hover karcie (pułapka z docka i wyspy).
    readonly property bool hovered: cardMouse.containsMouse || thumbMouse.containsMouse
        || editButton.hovering || folderButton.hovering || removeButton.hovering

    Timer {
        id: hideTimer
        interval: root.view === "error" ? root.errorHideMs : root.hideMs
        running: root.shown && root.view !== "countdown" && !root.hovered
        onTriggered: root.hide()
    }

    // ---------------------------------------------------------------
    // Karta
    // ---------------------------------------------------------------

    component ToastButton: Rectangle {
        id: button

        property string kind: ""
        property color tint: Theme.accent
        signal clicked()

        readonly property bool hovering: buttonMouse.containsMouse

        width: root.buttonSize
        height: root.buttonSize
        radius: height / 2
        // Pełny kolor, bez alfy (DESIGN.md): odcień zmieszany z tłem.
        color: hovering ? Qt.tint(Theme.surfaceRaised, Qt.rgba(tint.r, tint.g, tint.b, 0.2)) : Theme.surfaceRaised
        border.width: 1
        border.color: hovering ? tint : Theme.border
        scale: buttonMouse.pressed ? 0.9 : 1

        Behavior on color { ColorAnimation { duration: Theme.quickMs } }
        Behavior on border.color { ColorAnimation { duration: Theme.quickMs } }
        Behavior on scale { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.OutQuad } }

        Icon {
            anchors.centerIn: parent
            kind: button.kind
            size: 16
            color: button.hovering ? Theme.text : Theme.textDim
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    Rectangle {
        id: card

        x: root.edgeMargin + (1 - root.reveal) * (width + root.edgeMargin)
        y: parent.height - height - root.edgeMargin
        width: root.cardWidth
        height: root.view === "shot" ? root.thumbHeight + root.buttonSize + 3 * root.padding
              : root.view === "countdown" ? 64
              : Math.max(64, errorText.implicitHeight + 2 * 16)
        radius: 20
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        opacity: Math.min(1, root.reveal * 1.5)

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            // Klik w odliczanie albo błąd zamyka (odliczanie: anuluje zrzut).
            onClicked: {
                if (root.view === "shot") return;
                if (root.view === "countdown") ScreenshotService.cancelCountdown();
                root.hide();
            }
        }

        // ---- zrzut ----

        Item {
            anchors.fill: parent
            visible: root.view === "shot"

            ClippingRectangle {
                id: thumb

                x: root.padding
                y: root.padding
                width: parent.width - 2 * root.padding
                height: root.thumbHeight
                radius: 12
                color: Theme.surfaceRaised
                border.width: 1
                border.color: thumbMouse.containsMouse ? Theme.accent : Theme.border

                Behavior on border.color { ColorAnimation { duration: Theme.quickMs } }

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    source: root.view === "shot" && root.path !== "" ? "file://" + root.path : ""
                    asynchronous: true
                    // Ten sam plik po edycji ma inną treść: bez pamięci podręcznej.
                    cache: false
                    sourceSize: Qt.size(width * 2, height * 2)
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    id: thumbMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editButton.clicked()
                }
            }

            Column {
                x: root.padding + 4
                anchors.verticalCenter: buttons.verticalCenter
                width: buttons.x - x - 8
                spacing: 1

                Text {
                    width: parent.width
                    text: "Zrzut zapisany"
                    color: Theme.text
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: root.copied
                    text: "i skopiowany do schowka"
                    color: Theme.textDim
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Row {
                id: buttons

                anchors.right: parent.right
                anchors.rightMargin: root.padding
                y: thumb.y + thumb.height + root.padding
                spacing: 6

                ToastButton {
                    id: editButton
                    kind: "edit"
                    onClicked: {
                        ScreenshotService.edit(root.path, root.path);
                        root.hide();
                    }
                }

                ToastButton {
                    id: folderButton
                    kind: "folder"
                    onClicked: {
                        ScreenshotService.reveal(root.path);
                        root.hide();
                    }
                }

                ToastButton {
                    id: removeButton
                    kind: "trash"
                    tint: Theme.danger
                    onClicked: {
                        ScreenshotService.remove(root.path);
                        root.hide();
                    }
                }
            }
        }

        // ---- odliczanie ----

        Row {
            anchors.centerIn: parent
            visible: root.view === "countdown"
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.max(1, ScreenshotService.countdown)
                color: Theme.accent
                font.pixelSize: 28
                font.bold: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Zrzut za chwilę · klik anuluje"
                color: Theme.textDim
                font.pixelSize: 13
            }
        }

        // ---- błąd ----

        Icon {
            id: errorIcon
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            visible: root.view === "error"
            kind: "warning"
            size: 20
            color: Theme.danger
        }

        Text {
            id: errorText
            x: errorIcon.x + errorIcon.width + 12
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 16
            visible: root.view === "error"
            text: root.message
            textFormat: Text.PlainText
            color: Theme.text
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }
    }
}
