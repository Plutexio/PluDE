import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common

// Launcher: przyciemniony ekran, pole wyszukiwania i siatka aplikacji.
// Otwiera go przycisk w docku, SUPER+R (skrót globalny) i IPC.
//
// Klawiatura: pisanie od razu szuka, strzałki chodzą po siatce, Enter
// uruchamia, Esc albo klik obok zamyka. Prawy klik: przypnij / akcje.
PanelWindow {
    id: root

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    property int panelWidth: 760
    property int panelHeight: 540
    property int cellWidth: 118
    property int cellHeight: 112
    property int iconSize: 56
    property real dim: 0.45             // przyciemnienie tła (0–1)

    // ---- animacje ----
    // Przy otwarciu ikony wlatują falą po przekątnej: opóźnienie =
    // (wiersz + kolumna) × openStep. Przy pisaniu fali nie ma — niepasujące
    // znikają, a reszta przejeżdża na nowe miejsca (przejścia GridView).
    property int openStep: 22
    property int openCellMs: 420
    property int filterMs: 260

    // ---------------------------------------------------------------
    // Okno
    // ---------------------------------------------------------------

    screen: Settings.screen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "plude-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive, nie OnDemand: OnDemand daje klawiaturę dopiero po kliknięciu
    // w powierzchnię, a pole wyszukiwania ma łapać znaki od razu (lekcja
    // z formularza Wi-Fi w wyspie). Zamknięty launcher nie bierze niczego —
    // schowane okno z Exclusive zjadałoby wszystkie klawisze.
    WlrLayershell.keyboardFocus: LauncherService.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property bool open: LauncherService.open

    // reveal: 0 = panel schowany, 1 = na miejscu. Otwarcie sprężyste (OutBack),
    // zamknięcie krótkie i bez odbicia — launcher ma znikać od razu, kiedy
    // już wiadomo, co uruchomić.
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

    // Start animacji otwarcia dopiero, gdy okno "rozgrzeje się" po pokazaniu.
    // Pierwsze klatki to odtworzenie powierzchni i wgranie tekstur (zmierzone
    // FrameAnimation: ~60 ms, potem 26–37 ms, dopiero dalej równo 16,7 ms) —
    // animacja ruszająca od razu gubiła początek i szarpała. Czekamy na
    // pierwszą szybką klatkę (< 20 ms), najwyżej 8. Panel i przyciemnienie są
    // w tym czasie niewidoczne (reveal = 0), więc to opóźnienie nie razi.
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

    // Siatka stoi na ListModel synchronizowanym ruchami (jak rząd docka), NIE
    // na tablicy wyników. Tablica w modelu = przy każdej zmianie wszystkie
    // delegaty od nowa, a każdy ładuje ikonę synchronicznie. Zmierzone: pętla
    // zdarzeń stała ~450 ms przy pierwszym otwarciu i ~190 ms przy kolejnych,
    // więc animacja otwarcia w ogóle nie była widać. Tu delegaty żyją stale,
    // otwarcie tylko restartuje ich animację (sygnał cascade).
    ListModel { id: appModel }

    function syncModel(list) {
        const ids = list.map(e => e.id);
        for (let i = appModel.count - 1; i >= 0; i--)
            if (ids.indexOf(appModel.get(i).appId) < 0) appModel.remove(i);

        for (let i = 0; i < ids.length; i++) {
            if (i < appModel.count && appModel.get(i).appId === ids[i]) continue;
            let from = -1;
            for (let j = i + 1; j < appModel.count; j++)
                if (appModel.get(j).appId === ids[i]) { from = j; break; }
            if (from >= 0) appModel.move(from, i, 1);
            else appModel.insert(i, { appId: ids[i] });
        }
    }

    readonly property var results: LauncherService.search(search.text)
    onResultsChanged: {
        syncModel(results);
        grid.currentIndex = 0;
    }
    Component.onCompleted: syncModel(results)

    signal cascade()

    // Id aplikacji właśnie uruchamianej — jej ikona rośnie i się rozpływa.
    property string launchingId: ""

    onOpenChanged: {
        revealIn.stop();
        revealOut.stop();
        if (open) {
            launchingId = "";
            search.text = "";
            grid.currentIndex = 0;
            grid.positionViewAtBeginning();
            search.forceActiveFocus();
            revealPending = true;
        } else {
            menu.close();
            revealPending = false;
            revealOut.start();
        }
    }

    function launch(e) {
        if (!e) return;
        launchingId = e.id;
        Apps.launch(e, null);
        LauncherService.hide();
    }

    // ---------------------------------------------------------------
    // Tło: klik obok panelu zamyka
    // ---------------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        // Z reveal (przycięte do 1 — OutBack przestrzeliwuje), żeby tło nie
        // ciemniało przed pojawieniem się panelu.
        color: Qt.rgba(0, 0, 0, root.dim * Math.min(1, root.reveal))

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: LauncherService.hide()
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

        // 1% w trakcie oczekiwania: przy krycie 0 Qt nie rysuje panelu, więc
        // glify podpisów i tekstury ikon szły na GPU dopiero w drugiej klatce
        // animacji (zmierzone: ~36 ms zamiast 16,7). Tak robią się w czasie,
        // gdy panelu i tak nie widać.
        opacity: root.revealPending ? 0.01 : Math.min(1, root.reveal * 1.5)
        scale: 0.9 + 0.1 * root.reveal
        transform: Translate { y: (1 - root.reveal) * 28 }

        // Escape tutaj, nie w polu: TextInput nie połyka Escape, więc klawisz
        // idzie w górę drzewa i trafia do nas także z kursorem w polu.
        Keys.onEscapePressed: LauncherService.hide()

        Rectangle {
            anchors.fill: parent
            radius: 30
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            // Klik w samo tło panelu nie może przelecieć do przyciemnienia pod
            // spodem i zamknąć launchera.
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        }

        // ---- pole wyszukiwania ----

        Rectangle {
            id: field

            x: 24
            y: 24
            width: parent.width - 48
            height: 44
            radius: 22
            color: Theme.surfaceRaised
            border.width: 1
            border.color: search.activeFocus ? Qt.rgba(0.36, 0.55, 1, 0.5) : Theme.border

            // Lupa z dwóch kształtów — bez zależności od motywu ikon.
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

                // Pole jest źródłem prawdy dla swojej treści (pułapka z wyspy:
                // powiązanie text: z właściwością zrywa się przy pierwszym znaku).
                onTextChanged: grid.currentIndex = 0

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Down:  grid.moveCurrentIndexDown();  break;
                    case Qt.Key_Up:    grid.moveCurrentIndexUp();    break;
                    case Qt.Key_Right:
                        // Strzałki w bok chodzą po siatce tylko przy pustym polu
                        // albo kursorze na końcu tekstu — inaczej przesuwają kursor.
                        if (search.cursorPosition < search.text.length) return;
                        grid.moveCurrentIndexRight();
                        break;
                    case Qt.Key_Left:
                        if (search.cursorPosition > 0) return;
                        grid.moveCurrentIndexLeft();
                        break;
                    case Qt.Key_Tab:   grid.currentIndex = Math.min(grid.count - 1, grid.currentIndex + 1); break;
                    case Qt.Key_Backtab: grid.currentIndex = Math.max(0, grid.currentIndex - 1); break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.launch(grid.currentItem ? grid.currentItem.entry : null);
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }

                Text {
                    visible: search.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Szukaj aplikacji…"
                    color: Theme.textFaint
                    font.pixelSize: 16
                }
            }
        }

        // ---- siatka ----

        GridView {
            id: grid

            y: field.y + field.height + 16
            width: Math.floor((parent.width - 48) / root.cellWidth) * root.cellWidth
            height: parent.height - y - 20
            anchors.horizontalCenter: parent.horizontalCenter

            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            clip: true
            model: appModel
            boundsBehavior: Flickable.StopAtBounds
            // Zaznaczenie przepływa między ikonami zamiast przeskakiwać.
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 170
            keyNavigationWraps: false
            currentIndex: 0

            // Filtrowanie: znikające się kurczą, nowe wskakują, reszta przejeżdża.
            // Tylko przy otwartym launcherze: przy starcie wpisy .desktop
            // dochodzą pojedynczo (47 synchronizacji), a animacje niewidocznego
            // okna nie idą — odtwarzały się potem przy pierwszym otwarciu
            // z nieaktualnych pozycji (zmierzone: siatka przesunięta o 7 pól).
            add: Transition {
                enabled: root.open
                NumberAnimation { property: "scale"; from: 0.6; to: 1; duration: root.filterMs; easing.type: Easing.OutBack }
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.filterMs }
            }
            remove: Transition {
                enabled: root.open
                NumberAnimation { property: "scale"; to: 0.6; duration: root.filterMs * 0.6; easing.type: Easing.InCubic }
                NumberAnimation { property: "opacity"; to: 0; duration: root.filterMs * 0.6 }
            }
            move: Transition {
                enabled: root.open
                NumberAnimation { properties: "x,y"; duration: root.filterMs; easing.type: Easing.OutCubic }
            }
            displaced: Transition {
                enabled: root.open
                NumberAnimation { properties: "x,y"; duration: root.filterMs; easing.type: Easing.OutCubic }
                // Element przerwany w trakcie add/remove wraca do pełnej postaci.
                NumberAnimation { properties: "scale,opacity"; to: 1; duration: root.filterMs }
            }

            highlight: Rectangle {
                width: root.cellWidth
                height: root.cellHeight
                radius: 18
                color: Theme.hoverStrong
                // Pojawia się razem z ikoną, na której stoi — inaczej przy
                // otwarciu wisiałoby puste podświetlenie przed falą.
                opacity: grid.currentItem ? Math.min(1, grid.currentItem.enter) : 0
                // Wcięcie jak tło najechania; highlight ma rozmiar komórki.
                scale: (root.cellWidth - 8) / root.cellWidth
            }

            delegate: Item {
                id: cell

                required property string appId
                required property int index
                readonly property var entry: Apps.entry(appId)

                width: root.cellWidth
                height: root.cellHeight

                readonly property bool current: GridView.isCurrentItem
                readonly property bool pinned: Pins.has(appId)
                readonly property bool launching: root.launchingId === appId

                // ---- wlatywanie przy otwarciu ----
                // 0 → 1 z opóźnieniem z pozycji w siatce, liczonej od
                // pierwszego widocznego wiersza.
                readonly property int columns: Math.max(1, Math.floor(grid.width / root.cellWidth))
                property real enter: 1

                Connections {
                    target: root
                    function onCascade() {
                        const row = Math.floor(cell.index / cell.columns) - Math.floor(grid.contentY / root.cellHeight);
                        enterPause.duration = Math.max(0, row + cell.index % cell.columns) * root.openStep;
                        enterAnim.stop();
                        cell.enter = 0;
                        enterAnim.start();
                    }
                }

                SequentialAnimation {
                    id: enterAnim
                    PauseAnimation { id: enterPause }
                    NumberAnimation {
                        target: cell; property: "enter"; to: 1
                        duration: root.openCellMs
                        easing.type: Easing.OutBack; easing.overshoot: 1.4
                    }
                }

                // ---- najechanie / wciśnięcie / uruchomienie ----
                property real hover: cellMouse.containsMouse ? 1 : 0
                Behavior on hover { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.005 } }
                property real press: cellMouse.pressed ? 1 : 0
                Behavior on press { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.OutQuad } }
                property real zoom: launching ? 1 : 0
                Behavior on zoom { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                Item {
                    id: content

                    anchors.fill: parent
                    opacity: Math.min(1, cell.enter) * (1 - cell.zoom)
                    scale: 0.7 + 0.3 * cell.enter
                    transform: Translate { y: (1 - cell.enter) * 18 }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 18
                        color: Theme.hover
                        // Aktualny ma podświetlenie z GridView.highlight, które przepływa.
                        opacity: cellMouse.containsMouse && !cell.current ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
                    }

                    Image {
                        id: icon
                        x: Math.round((parent.width - width) / 2)
                        y: 14
                        width: root.iconSize
                        height: root.iconSize
                        // Rośnie od dołu (nad podpisem), przy uruchomieniu wybucha.
                        transformOrigin: Item.Bottom
                        scale: (1 + 0.1 * cell.hover) * (1 - 0.1 * cell.press) * (1 + 0.7 * cell.zoom)
                        source: Apps.iconFor(cell.entry)
                        // Synchronicznie — patrz DockItem (image://icon a wątki).
                        asynchronous: false
                        // Pod największe powiększenie (najechanie × uruchomienie) — ostrość.
                        sourceSize: Qt.size(Math.ceil(root.iconSize * 1.3), Math.ceil(root.iconSize * 1.3))
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                    }

                    // Kropka przypięcia przy ikonie.
                    Rectangle {
                        scale: cell.pinned ? 1 : 0
                        visible: scale > 0
                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                        x: icon.x + icon.width - 4
                        y: icon.y - 2
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.accent
                        border.width: 2
                        border.color: Theme.surface
                    }

                    Text {
                        x: 8
                        y: icon.y + icon.height + 8
                        width: parent.width - 16
                        horizontalAlignment: Text.AlignHCenter
                        text: cell.entry ? cell.entry.name : ""
                        color: Theme.text
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) root.openMenu(cell, cell.entry);
                        else root.launch(cell.entry);
                    }
                }
            }

            Text {
                opacity: grid.count === 0 && search.text !== "" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.fadeMs } }
                anchors.centerIn: parent
                text: "Nic nie pasuje do „" + search.text + "”"
                color: Theme.textDim
                font.pixelSize: 14
            }
        }
    }

    // ---------------------------------------------------------------
    // Menu
    // ---------------------------------------------------------------

    PopupMenu { id: menu }

    function openMenu(cell, e) {
        const p = cell.mapToItem(root.contentItem, cell.width / 2, 8);
        const out = [{ header: e.name }, { text: "Uruchom", run: () => root.launch(e) }];
        const actions = e.actions || [];
        for (let i = 0; i < actions.length; i++) {
            const a = actions[i];
            out.push({
                text: a.name,
                icon: a.icon ? Quickshell.iconPath(a.icon, true) : "",
                run: () => { Apps.launch(e, a); LauncherService.hide(); }
            });
        }
        out.push({ separator: true });
        out.push({ text: Pins.has(e.id) ? "Odepnij z docka" : "Przypnij do docka", run: () => Pins.toggle(e.id) });
        menu.openAt(root, p.x, p.y, out);
    }
}
