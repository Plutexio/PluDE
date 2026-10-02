import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.PluScreenshot

// Historia schowka: przyciemniony ekran, pole wyszukiwania i lista wpisów,
// ten sam wzorzec co launcher. Otwiera ją SUPER+SHIFT+V (skrót globalny),
// wpis „Schowek” w launcherze i IPC.
//
// Klawiatura: pisanie od razu szuka, strzałki chodzą po liście, Enter
// wkleja (albo tylko kopiuje, patrz ClipboardService.pastes), Delete usuwa,
// Ctrl+P przypina, Esc albo klik obok zamyka. Prawy klik: menu wpisu.
PanelWindow {
    id: root

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    property int panelWidth: 640
    property int panelHeight: 560
    property int rowHeight: 60
    property int thumbSize: 44
    property real dim: 0.45             // przyciemnienie tła (0–1)

    // ---- animacje ----
    // Przy otwarciu wiersze wchodzą falą z góry na dół. Dalsze niż
    // cascadeRows wchodzą razem z ostatnim: są pod krawędzią panelu.
    property int openStep: 24
    property int openRowMs: 380
    property int cascadeRows: 9
    property int filterMs: 240

    // ---------------------------------------------------------------
    // Okno
    // ---------------------------------------------------------------

    screen: ClipboardService.screen ?? Settings.screen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "plude-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    // Jak launcher: Exclusive tylko przy otwartym oknie.
    WlrLayershell.keyboardFocus: ClipboardService.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property bool open: ClipboardService.open

    // reveal i revealPending działają jak w launcherze (tam opis pomiarów):
    // otwarcie sprężyste i dopiero po rozgrzaniu okna, zamknięcie krótkie.
    property real reveal: 0
    NumberAnimation {
        id: revealIn
        target: root; property: "reveal"; to: 1
        duration: 440; easing.type: Easing.OutBack; easing.overshoot: 1.1
    }
    NumberAnimation {
        id: revealOut
        target: root; property: "reveal"; to: 0
        duration: 170; easing.type: Easing.InCubic
    }

    visible: open || reveal > 0

    property bool revealPending: false
    FrameAnimation {
        running: root.revealPending
        onTriggered: {
            if (currentFrame < 2 || (frameTime > 0.02 && currentFrame < 8)) return;
            root.revealPending = false;
            root.cascade();
            revealIn.start();
        }
    }

    // Lista stoi na ListModel synchronizowanym ruchami, jak siatka launchera:
    // nowy wpis wsuwa się na górę, a reszta zjeżdża, zamiast powstawać od nowa.
    ListModel { id: clipModel }

    function syncModel(list) {
        const ids = list.map(e => e.id);
        for (let i = clipModel.count - 1; i >= 0; i--)
            if (ids.indexOf(clipModel.get(i).entryId) < 0) clipModel.remove(i);

        for (let i = 0; i < ids.length; i++) {
            if (i < clipModel.count && clipModel.get(i).entryId === ids[i]) continue;
            let from = -1;
            for (let j = i + 1; j < clipModel.count; j++)
                if (clipModel.get(j).entryId === ids[i]) { from = j; break; }
            if (from >= 0) clipModel.move(from, i, 1);
            else clipModel.insert(i, { entryId: ids[i] });
        }
    }

    readonly property var results: ClipboardService.search(search.text)
    onResultsChanged: syncModel(results)
    Component.onCompleted: syncModel(results)

    signal cascade()

    // Czas „teraz” dla podpisów (5 min, wczoraj): liczony przy otwarciu,
    // żeby powiązania wierszy nie zależały od zegara.
    property double now: Date.now()

    onOpenChanged: {
        revealIn.stop();
        revealOut.stop();
        if (open) {
            now = Date.now();
            search.text = "";
            list.currentIndex = 0;
            list.positionViewAtBeginning();
            search.forceActiveFocus();
            revealPending = true;
        } else {
            menu.close();
            revealPending = false;
            revealOut.start();
        }
    }

    readonly property var currentEntry: list.currentItem ? list.currentItem.entry : null

    function removeCurrent() {
        if (currentEntry) ClipboardService.remove(currentEntry.id);
    }

    // ---------------------------------------------------------------
    // Tło: klik obok panelu zamyka
    // ---------------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.dim * Math.min(1, root.reveal))

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: ClipboardService.hide()
        }
    }

    // ---------------------------------------------------------------
    // Panel
    // ---------------------------------------------------------------

    FocusScope {
        id: scope

        width: root.panelWidth
        height: root.panelHeight
        anchors.centerIn: parent
        focus: true

        // 1% w trakcie oczekiwania: patrz launcher (tekstury przed animacją).
        opacity: root.revealPending ? 0.01 : Math.min(1, root.reveal * 1.5)
        scale: 0.9 + 0.1 * root.reveal
        transform: Translate { y: (1 - root.reveal) * 28 }

        Keys.onEscapePressed: ClipboardService.hide()

        Rectangle {
            anchors.fill: parent
            radius: 30
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            // Klik w tło panelu nie może przelecieć do przyciemnienia.
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        }

        // ---- pole wyszukiwania ----

        Rectangle {
            id: field

            x: 24
            y: 24
            width: parent.width - 48 - clearButton.width - 10
            height: 44
            radius: 22
            color: Theme.surfaceRaised
            border.width: 1
            border.color: search.activeFocus ? Qt.rgba(0.36, 0.55, 1, 0.5) : Theme.border

            // Lupa z dwóch kształtów, jak w launcherze.
            Item {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.textDim
                }
                Rectangle {
                    x: 10; y: 11
                    width: 7; height: 2; radius: 1
                    rotation: 45
                    color: Theme.textDim
                }
            }

            TextInput {
                id: search

                x: 44
                width: parent.width - x - 16
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text
                selectionColor: Theme.accent
                font.pixelSize: 16
                clip: true
                focus: true

                onTextChanged: list.currentIndex = 0

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Down:
                    case Qt.Key_Tab:
                        list.incrementCurrentIndex();
                        break;
                    case Qt.Key_Up:
                    case Qt.Key_Backtab:
                        list.decrementCurrentIndex();
                        break;
                    case Qt.Key_PageDown:
                        list.currentIndex = Math.min(list.count - 1, list.currentIndex + list.pageRows);
                        break;
                    case Qt.Key_PageUp:
                        list.currentIndex = Math.max(0, list.currentIndex - list.pageRows);
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        if (root.currentEntry) ClipboardService.choose(root.currentEntry.id);
                        break;
                    case Qt.Key_Delete:
                        // Z kursorem w środku tekstu Delete kasuje znak, jak zwykle.
                        if (search.cursorPosition < search.text.length || search.selectedText !== "") return;
                        root.removeCurrent();
                        break;
                    case Qt.Key_P:
                        if (!(event.modifiers & Qt.ControlModifier)) return;
                        if (root.currentEntry) ClipboardService.togglePin(root.currentEntry.id);
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }

                Text {
                    visible: search.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Szukaj w schowku…"
                    color: Theme.textFaint
                    font.pixelSize: 16
                }
            }
        }

        // ---- wyczyść ----

        Rectangle {
            id: clearButton

            readonly property bool active: ClipboardService.unpinnedCount > 0
            readonly property bool hovering: clearMouse.containsMouse && active

            anchors.right: parent.right
            anchors.rightMargin: 24
            y: field.y
            width: clearLabel.implicitWidth + 32
            height: field.height
            radius: height / 2
            // Pełny kolor, bez alfy (DESIGN.md): danger zmieszany z tłem.
            color: hovering ? Qt.tint(Theme.surfaceRaised, Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.22))
                            : Theme.surfaceRaised
            border.width: 1
            border.color: hovering ? Theme.danger : Theme.border
            opacity: active ? 1 : 0.4
            scale: clearMouse.pressed && active ? 0.95 : 1

            Behavior on color { ColorAnimation { duration: Theme.quickMs } }
            Behavior on border.color { ColorAnimation { duration: Theme.quickMs } }
            Behavior on opacity { NumberAnimation { duration: Theme.fadeMs } }
            Behavior on scale { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.OutQuad } }

            Text {
                id: clearLabel
                anchors.centerIn: parent
                text: "Wyczyść"
                color: clearButton.hovering ? Theme.text : Theme.textDim
                font.pixelSize: 13
            }

            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: clearButton.active ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (clearButton.active) ClipboardService.clear();
                    search.forceActiveFocus();
                }
            }
        }

        // ---- lista ----

        ListView {
            id: list

            readonly property int pageRows: Math.max(1, Math.floor(height / root.rowHeight) - 1)

            x: 16
            y: field.y + field.height + 14
            width: parent.width - 32
            height: hints.y - y - 8

            clip: true
            model: clipModel
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 150
            highlightResizeDuration: 0
            keyNavigationWraps: false
            currentIndex: 0

            // Przejścia tylko przy otwartym oknie, jak w launcherze: animacje
            // niewidocznego okna odtwarzały się potem z nieaktualnych pozycji.
            add: Transition {
                enabled: root.open
                NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: root.filterMs; easing.type: Easing.OutBack }
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.filterMs }
            }
            remove: Transition {
                enabled: root.open
                NumberAnimation { property: "scale"; to: 0.9; duration: root.filterMs * 0.6; easing.type: Easing.InCubic }
                NumberAnimation { property: "opacity"; to: 0; duration: root.filterMs * 0.6 }
            }
            move: Transition {
                enabled: root.open
                NumberAnimation { properties: "x,y"; duration: root.filterMs; easing.type: Easing.OutCubic }
            }
            displaced: Transition {
                enabled: root.open
                NumberAnimation { properties: "x,y"; duration: root.filterMs; easing.type: Easing.OutCubic }
                NumberAnimation { properties: "scale,opacity"; to: 1; duration: root.filterMs }
            }

            highlight: Rectangle {
                radius: 16
                color: Theme.hoverStrong
                opacity: list.currentItem ? Math.min(1, list.currentItem.enter) : 0
            }

            delegate: Item {
                id: row

                required property string entryId
                required property int index
                // Wpis usunięty z historii żyje jeszcze przez przejście remove.
                readonly property var entry: ClipboardService.byId[entryId] ?? null
                readonly property string flavor: entry ? ClipboardService.flavor(entry) : "text"
                readonly property bool current: ListView.isCurrentItem

                width: list.width
                height: root.rowHeight

                // ---- wchodzenie przy otwarciu ----
                property real enter: 1

                Connections {
                    target: root
                    function onCascade() {
                        const visibleRow = row.index - Math.floor(list.contentY / root.rowHeight);
                        enterPause.duration = Math.max(0, Math.min(root.cascadeRows, visibleRow)) * root.openStep;
                        enterAnim.stop();
                        row.enter = 0;
                        enterAnim.start();
                    }
                }

                SequentialAnimation {
                    id: enterAnim
                    PauseAnimation { id: enterPause }
                    NumberAnimation {
                        target: row; property: "enter"; to: 1
                        duration: root.openRowMs
                        easing.type: Easing.OutBack; easing.overshoot: 1.4
                    }
                }

                property real press: rowMouse.pressed ? 1 : 0
                Behavior on press { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.OutQuad } }

                Item {
                    anchors.fill: parent
                    opacity: Math.min(1, row.enter)
                    scale: 1 - 0.02 * row.press
                    transform: Translate { y: (1 - row.enter) * 14 }

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: Theme.hover
                        // Bieżący ma podświetlenie z ListView.highlight, które przepływa.
                        opacity: rowMouse.containsMouse && !row.current ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
                    }

                    // Miniatura obrazu, próbka koloru albo ikona rodzaju.
                    ClippingRectangle {
                        id: thumb

                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.thumbSize
                        height: root.thumbSize
                        radius: 12
                        color: row.flavor === "color" && row.entry ? row.entry.preview.trim() : Theme.surfaceRaised
                        border.width: 1
                        border.color: Theme.border

                        Image {
                            anchors.fill: parent
                            visible: row.flavor === "image"
                            source: row.flavor === "image" && row.entry ? "file://" + ClipboardService.path(row.entry) : ""
                            // Plik z dysku, nie image://icon: może ładować się w tle.
                            asynchronous: true
                            sourceSize: Qt.size(root.thumbSize * 2, root.thumbSize * 2)
                            fillMode: Image.PreserveAspectCrop
                        }

                        Icon {
                            anchors.centerIn: parent
                            visible: row.flavor === "text" || row.flavor === "link"
                            kind: row.flavor === "link" ? "link" : "text"
                            size: 20
                            color: row.flavor === "link" ? Theme.accent : Theme.textDim
                        }
                    }

                    Text {
                        id: titleText

                        x: thumb.x + thumb.width + 14
                        y: 11
                        width: parent.width - x - 14 - (pinMark.visible ? 26 : 0)
                        text: row.entry ? ClipboardService.title(row.entry) : ""
                        // Podgląd to dowolny tekst ze schowka: bez interpretowania znaczników.
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        x: titleText.x
                        y: titleText.y + titleText.height + 4
                        width: titleText.width
                        text: row.entry ? ClipboardService.detail(row.entry) + " · " + ClipboardService.ago(row.entry.time, root.now) : ""
                        color: Theme.textDim
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Icon {
                        id: pinMark

                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "pin"
                        size: 16
                        color: Theme.accent
                        scale: row.entry && row.entry.pinned ? 1 : 0
                        visible: scale > 0
                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (!row.entry) return;
                        list.currentIndex = row.index;
                        if (mouse.button === Qt.RightButton) root.openMenu(row, mouse.x, row.entry);
                        else ClipboardService.choose(row.entry.id);
                    }
                }
            }

            Text {
                opacity: list.count === 0 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.fadeMs } }
                anchors.centerIn: parent
                width: parent.width - 80
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: search.text !== "" ? "Nic nie pasuje do „" + search.text + "”"
                                         : "Schowek jest pusty. Skopiuj coś, a pojawi się tutaj."
                color: Theme.textDim
                font.pixelSize: 14
            }
        }

        // ---- podpowiedź klawiszy ----

        Row {
            id: hints

            x: 28
            y: parent.height - height - 16
            spacing: 14

            component Hint: Row {
                property string key: ""
                property string label: ""
                property color tint: Theme.accent
                spacing: 5
                Text { text: parent.key; color: parent.tint; font.pixelSize: 12 }
                Text { text: parent.label; color: Theme.textFaint; font.pixelSize: 12 }
            }

            Hint { key: "enter"; label: ClipboardService.pastes ? "wklej" : "kopiuj" }
            Hint { key: "del"; label: "usuń" }
            Hint { key: "ctrl+p"; label: "przypnij" }
            Hint { key: "esc"; label: "zamknij"; tint: Theme.warning }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.verticalCenter: hints.verticalCenter
            text: {
                const n = ClipboardService.items.length;
                return n + " " + ClipboardService.plural(n, "wpis", "wpisy", "wpisów");
            }
            color: Theme.textFaint
            font.pixelSize: 12
        }
    }

    // ---------------------------------------------------------------
    // Menu
    // ---------------------------------------------------------------

    PopupMenu { id: menu }

    function openMenu(row, x, e) {
        const p = row.mapToItem(root.contentItem, x, 8);
        const out = [
            { header: ClipboardService.detail(e) },
            { text: ClipboardService.pastes ? "Wklej" : "Kopiuj", run: () => ClipboardService.choose(e.id) },
            { text: e.pinned ? "Odepnij" : "Przypnij", run: () => ClipboardService.togglePin(e.id) }
        ];
        if (e.kind === "image")
            out.push({ text: "Edytuj w swappy", run: () => {
                ClipboardService.hide();
                ScreenshotService.edit(ClipboardService.path(e), ScreenshotService.newPath());
            } });
        out.push({ separator: true });
        out.push({ text: "Usuń", danger: true, run: () => ClipboardService.remove(e.id) });
        menu.openAt(root, p.x, p.y, out);
    }
}
