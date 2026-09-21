import QtQuick
import Quickshell
import qs.Common

// Jeden element docka: ikona aplikacji, przycisk launchera albo separator.
//
// Delegat NIE obsługuje myszy — robi to jedna MouseArea na całym docku
// (Dock.qml), która po pozycji kursora wie, nad którym elementem jest.
// Tu tylko rysujemy stan, który dock ustawia (hovered, pressed, placeholder).
Item {
    id: item

    required property string key
    required property int index

    // Ustawiane przez dock.
    property int cellWidth: 56
    property int iconSize: 44
    property int separatorWidth: 13
    property bool hovered: false
    property bool pressed: false
    // Element przeciągany: jego miejsce w rzędzie zostaje, a ikonę niesie
    // "duch" w oknie docka — tu rysujemy pustą szczelinę.
    property bool placeholder: false

    // ---- animacje (ustawiane przez dock) ----
    //
    // magScale: powiększenie tej ikony (1 = bez). Liczy je dock razem z
    // szerokością elementu — to on rozsuwa rząd. maxScale: największe możliwe,
    // pod ostrość ikony (sourceSize).
    property real magScale: 1
    property real maxScale: 1

    // shown: czy dock jest wysunięty. appearDelay: opóźnienie wskoczenia
    // tej ikony przy wysuwaniu (dock daje falę od środka na zewnątrz).
    property bool shown: true
    property int appearDelay: 0

    readonly property bool isSeparator: key === DockService.separatorKey
    readonly property bool isLauncher: key === DockService.launcherKey
    readonly property bool isApp: !isSeparator && !isLauncher

    // Wywołania funkcji w powiązaniach przeliczają się, bo funkcje DockService
    // czytają jego WŁAŚCIWOŚCI (groups, activeKey, …) — to one są zależnością.
    readonly property var windows: isApp ? DockService.windowsFor(key) : []
    readonly property bool running: windows.length > 0
    readonly property bool active: isApp && DockService.activeKey === key
    readonly property bool launching: isApp && DockService.isLaunching(key)
    readonly property int unseen: isApp ? DockService.unseenCount(key) : 0
    readonly property var job: isApp ? IslandLink.jobFor(key) : null
    readonly property bool playing: isApp && DockService.playingKeys.indexOf(key) >= 0
    readonly property var call: isApp && DockService.callKey === key ? IslandLink.discord : null

    // Obszar plakietki we współrzędnych elementu — dock sprawdza, czy klik
    // trafił w plakietkę (klik w nią otwiera powiadomienia w wyspie).
    function badgeContains(x, y) {
        if (unseen === 0) return false;
        const p = item.mapToItem(badge, x, y);
        return p.x >= -4 && p.y >= -4 && p.x <= badge.width + 4 && p.y <= badge.height + 4;
    }

    width: isSeparator ? separatorWidth : cellWidth
    height: parent ? parent.height : 64

    // 0 = ikona schowana w docku, 1 = na miejscu. Wysuwanie: od środka na
    // zewnątrz, z odbiciem (appearDelay). Chowanie: odwrotnie, od krawędzi do
    // środka (disappearDelay), z zamachem InBack — ikona lekko podskakuje
    // i dopiero wtedy zapada się w dock. Dock zaczyna zjeżdżać chwilę później.
    property int disappearDelay: 0
    // Zwykła wartość ustawiana raz, NIE powiązanie `shown ? 1 : 0`: animacja
    // powiązania nie zrywa, więc przy chowaniu wracało ono od razu do 0
    // i ikony z opóźnieniem znikały bez animacji (zmierzone: środkowe 0,00
    // po 50 ms, gdy skrajne dopiero zaczynały).
    property real appear: 0
    // Element utworzony przy wysuniętym docku (nowe okno, przypięcie)
    // wskakuje tak samo jak przy wysuwaniu — to zastępuje przejście add z Row.
    Component.onCompleted: if (shown) appearAnim.start()
    onShownChanged: {
        appearAnim.stop();
        disappearAnim.stop();
        if (shown) {
            // Z bieżącej wartości, nie od zera: dock wysunięty w trakcie
            // chowania nie mruga pustymi ikonami.
            appearAnim.start();
        } else {
            disappearAnim.start();
        }
    }
    SequentialAnimation {
        id: appearAnim
        PauseAnimation { duration: item.appear < 0.5 ? item.appearDelay : 0 }
        NumberAnimation {
            target: item; property: "appear"; to: 1
            duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.6
        }
    }
    SequentialAnimation {
        id: disappearAnim
        PauseAnimation { duration: item.disappearDelay }
        NumberAnimation {
            target: item; property: "appear"; to: 0
            duration: 240; easing.type: Easing.InBack; easing.overshoot: 2.2
        }
    }

    // ---- separator ----

    Rectangle {
        visible: item.isSeparator
        anchors.centerIn: parent
        width: 1
        height: Math.round(item.iconSize * 0.7)
        opacity: item.appear
        color: Qt.rgba(1, 1, 1, 0.14)
    }

    // ---- ikona ----

    Item {
        id: iconHolder

        visible: !item.isSeparator
        width: item.iconSize
        height: item.iconSize
        x: Math.round((item.width - width) / 2)
        // Dwa piksele wyżej niż środek — pod spodem wiszą kropki okien.
        y: Math.round((item.height - height) / 2) - 2

        opacity: item.placeholder ? 0 : item.appear
        scale: item.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.OutQuad } }

        // Kolejność: powiększenie (skala od dołu ikony — rośnie w górę, nie
        // w kropki; razem z nią plakietki, jak w macOS), wskakiwanie przy
        // wysuwaniu, skok przy uruchamianiu. Skok ma osobny Translate: jego
        // animacja pętli się sama i nie może walczyć z powiązaniami pozostałych.
        transform: [
            Scale {
                origin.x: item.iconSize / 2
                origin.y: item.iconSize
                xScale: item.magScale * (0.6 + 0.4 * item.appear)
                yScale: xScale
            },
            Translate { y: (1 - item.appear) * 26 },
            Translate { id: lift; y: 0 }
        ]

        // Skok przy uruchamianiu. alwaysRunToEnd: ikona dokańcza skok i
        // ląduje, zamiast zawisnąć w powietrzu, gdy okno pojawi się w trakcie.
        SequentialAnimation {
            running: item.launching
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { target: lift; property: "y"; to: -14; duration: 280; easing.type: Easing.OutQuad }
            NumberAnimation { target: lift; property: "y"; to: 0; duration: 280; easing.type: Easing.InQuad }
            PauseAnimation { duration: 140 }
        }

        // Tło pod kursorem — w środku ikony, żeby unosiło się i rosło razem z nią.
        // +8 do parzystej ikony: dodatek parzysty, inaczej wyśrodkowanie
        // zaokrągla pół piksela w jedną stronę (pułapka z wyspy).
        Rectangle {
            x: -4
            y: -4
            width: item.iconSize + 8
            height: item.iconSize + 8
            radius: Math.round(item.iconSize * 0.3)
            color: item.pressed ? Theme.hoverStrong : Theme.hover
            opacity: (item.hovered || item.pressed) && !item.placeholder ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
        }

        Image {
            visible: item.isApp
            anchors.fill: parent
            source: item.isApp ? DockService.iconFor(item.key) : ""
            // Synchronicznie: dostawca image://icon nie jest wątkowo bezpieczny
            // ("Cannot create children for a parent that is in a different
            // thread" — zmierzone w wyspie). sourceSize w px logicznych: Qt
            // sam mnoży przez skalę ekranu (zmierzone: 56 → żądanie 224 przy
            // dawnym ×2 i skali 2).
            asynchronous: false
            // Pod największe powiększenie — inaczej powiększona ikona to
            // rozciągnięta mała bitmapa.
            sourceSize: Qt.size(Math.ceil(item.iconSize * item.maxScale), Math.ceil(item.iconSize * item.maxScale))
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }

        // Launcher: siatka 3×3 kropek, bez ikony z motywu — ma wyglądać tak
        // samo niezależnie od motywu ikon.
        Grid {
            visible: item.isLauncher
            anchors.centerIn: parent
            columns: 3
            spacing: dot
            // Kropki skalują się z ikoną: 7 + 7 + 7 z odstępami ≈ 5/7 ikony.
            readonly property int dot: Math.round(item.iconSize / 7)
            Repeater {
                model: 9
                Rectangle { width: parent.dot; height: parent.dot; radius: width / 2; color: Theme.text }
            }
        }

        // ---- plakietka powiadomień (prawy górny róg) ----

        Rectangle {
            id: badge

            readonly property string label: item.unseen > 9 ? "9+" : String(item.unseen)

            x: parent.width - width + 5
            y: -5
            width: Math.max(18, badgeText.implicitWidth + 10)
            height: 18
            radius: 9
            color: Theme.danger
            border.width: 2
            border.color: Theme.surface

            scale: item.unseen > 0 ? 1 : 0
            visible: scale > 0
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

            Text {
                id: badgeText
                anchors.centerIn: parent
                text: badge.label
                color: "white"
                font.pixelSize: 10
                font.bold: true
            }
        }

        // ---- odtwarzanie (lewy górny róg): trzy skaczące słupki ----

        Rectangle {
            x: -5
            y: -5
            width: 18
            height: 18
            radius: 9
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            scale: item.playing ? 1 : 0
            visible: scale > 0
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

            Row {
                anchors.centerIn: parent
                height: 9
                spacing: 2
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: 2
                        radius: 1
                        // y ręcznie, nie anchors.bottom — w Row kotwice w osi
                        // prostopadłej gryzą się z pozycjonerem.
                        y: 9 - height
                        color: Theme.success
                        height: 4
                        SequentialAnimation on height {
                            running: item.playing
                            loops: Animation.Infinite
                            NumberAnimation { to: 9; duration: 260 + index * 70; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 3; duration: 260 + index * 70; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }
        }

        // ---- rozmowa głosowa (prawy dolny róg) ----

        Rectangle {
            x: parent.width - width + 4
            y: parent.height - height + 4
            width: 14
            height: 14
            radius: 7
            color: item.call && (item.call.muted || item.call.deafened) ? Theme.danger : Theme.success
            border.width: 2
            border.color: Theme.surface

            scale: item.call && item.call.inVoice ? 1 : 0
            visible: scale > 0
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
        }

        // ---- postęp transferu (na dole ikony) ----

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            width: parent.width - 8
            height: 6
            radius: 3
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
            visible: item.job !== null

            Rectangle {
                x: 1
                y: 1
                height: parent.height - 2
                radius: height / 2
                color: Theme.accent
                width: item.job ? Math.max(height, (parent.width - 2) * Math.max(0, Math.min(1, item.job.progress))) : 0
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }
    }

    // ---- kropki okien ----
    //
    // Do trzech kropek, po jednej na okno; aktywna aplikacja ma zamiast nich
    // jedną szerszą, jaśniejszą kreskę.

    Row {
        visible: item.isApp && item.running && !item.placeholder
        opacity: item.appear
        anchors.horizontalCenter: parent.horizontalCenter
        y: item.height - 8
        spacing: 3

        Repeater {
            model: item.active ? 1 : Math.min(3, item.windows.length)
            Rectangle {
                width: item.active ? 14 : 4
                height: 4
                radius: 2
                color: item.active ? Theme.text : Theme.textDim
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        }
    }
}
