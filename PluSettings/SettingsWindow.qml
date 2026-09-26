import QtQuick
import Quickshell
import qs.Common

// ---------------------------------------------------------------
// Okno ustawień: zwykła aplikacja (xdg toplevel), nie warstwa jak dock.
// Ma normalny fokus klawiatury, da się je przesunąć, a w docku stoi
// z kropką jak każde okno. Klasa to org.quickshell (FloatingWindow nie ma
// appId), dlatego:
//   - pływające i wyśrodkowane jest z reguły w hyprland.lua (po tytule),
//   - w docku i launcherze to „Ustawienia PluDE” dzięki lokalnemu
//     ~/.local/share/applications/org.quickshell.desktop.
//
// Tworzone przez LazyLoader w Main.qml, gdy SettingsApp.shown.
// ---------------------------------------------------------------
FloatingWindow {
    id: win

    property int sidebarWidth: 208
    property int contentMargin: 28
    property int contentMaxWidth: 640

    title: SettingsApp.windowTitle
    color: Theme.surface
    // Rozmiar startowy ustawia reguła Hyprlanda; to jest zapas bez niej.
    implicitWidth: 780
    implicitHeight: 560
    minimumSize: Qt.size(640, 420)

    // Zamknięcie przez kompozytor (SUPER+C) daje visible = false
    // (zmierzone) — wtedy zwalniamy okno, żeby następne otwarcie było czyste.
    onVisibleChanged: if (!visible) SettingsApp.close()

    FocusScope {
        anchors.fill: parent
        focus: true

        // Esc zamyka, jak launcher. Pole tekstowe połyka swój Esc samo.
        Keys.onEscapePressed: SettingsApp.close()

        // Tło też w środku, nie tylko jako kolor okna: grabToImage łapie
        // elementy, a nie okno, i bez tego zrzut wychodzi przezroczysty.
        Rectangle {
            anchors.fill: parent
            color: Theme.surface
        }

        // Klik w puste miejsce zabiera fokus polu (i zapisuje je).
        MouseArea {
            anchors.fill: parent
            onPressed: mouse => { parent.forceActiveFocus(); mouse.accepted = false; }
        }

        // ---- pasek boczny ----

        Column {
            id: sidebar
            x: 14
            y: 18
            width: win.sidebarWidth - 28
            spacing: 2

            Text {
                x: 10
                height: 40
                verticalAlignment: Text.AlignVCenter
                text: "Ustawienia"
                color: Theme.text
                font.pixelSize: 16
                font.bold: true
            }

            Repeater {
                model: SettingsApp.pages

                Rectangle {
                    id: navItem

                    required property var modelData
                    readonly property bool current: SettingsApp.page === modelData.id

                    width: sidebar.width
                    height: 36
                    radius: 10
                    // Pełne kolory, bez alfy (DESIGN.md): akcent zmieszany z tłem.
                    color: current ? Qt.tint(Theme.surface, Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2))
                        : navMouse.containsMouse ? Theme.surfaceRaised : Theme.surface

                    Behavior on color { ColorAnimation { duration: Theme.quickMs } }

                    Icon {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        kind: navItem.modelData.icon
                        size: 18
                        color: navItem.current ? Theme.accent : Theme.textDim
                    }

                    Text {
                        x: 38
                        anchors.verticalCenter: parent.verticalCenter
                        text: navItem.modelData.title
                        color: navItem.current || navMouse.containsMouse ? Theme.text : Theme.textDim
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: navMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SettingsApp.page = navItem.modelData.id
                    }
                }
            }
        }

        Rectangle {
            x: win.sidebarWidth
            width: 1
            height: parent.height
            color: Theme.border
        }

        // ---- treść ----

        Flickable {
            id: flick

            x: win.sidebarWidth + 1
            width: parent.width - x
            height: parent.height
            clip: true
            contentHeight: body.height + 2 * win.contentMargin
            boundsBehavior: Flickable.StopAtBounds

            // Klik w puste miejsce strony też zdejmuje fokus z pola — tu
            // zdarzenie bierze Flickable, więc MouseArea okna go nie widzi.
            MouseArea {
                width: flick.width
                height: Math.max(flick.height, flick.contentHeight)
                onPressed: mouse => { flick.forceActiveFocus(); mouse.accepted = false; }
            }

            // Przewinięcie na górę przy zmianie strony.
            Connections {
                target: SettingsApp
                function onPageChanged() {
                    choiceMenu.close();
                    flick.contentY = 0;
                }
            }

            // Lista liczy pozycję raz, przy otwarciu — przewinięta strona
            // odjechałaby od niej.
            onContentYChanged: choiceMenu.close()

            Column {
                id: body

                x: Math.max(win.contentMargin, (flick.width - width) / 2)
                y: win.contentMargin
                width: Math.min(win.contentMaxWidth, flick.width - 2 * win.contentMargin)
                spacing: 20

                Text {
                    text: {
                        const p = SettingsApp.pages.find(p => p.id === SettingsApp.page);
                        return p ? p.title : "";
                    }
                    color: Theme.text
                    font.pixelSize: 16
                    font.bold: true
                }

                Loader {
                    id: pageLoader

                    width: body.width
                    sourceComponent: SettingsApp.page === "monitors" ? monitorsPage : generalPage

                    // Krótkie wejście strony: bez odbicia, to tylko zmiana treści.
                    property real enter: 1
                    opacity: enter
                    transform: Translate { y: (1 - pageLoader.enter) * 8 }
                    onLoaded: {
                        enter = 0;
                        enterAnim.restart();
                    }

                    NumberAnimation {
                        id: enterAnim
                        target: pageLoader
                        property: "enter"
                        to: 1
                        duration: Theme.fadeMs
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Rozwinięte listy wyboru — nad stroną, pod potwierdzeniem.
        ChoiceMenu {
            id: choiceMenu
            anchors.fill: parent
            Component.onCompleted: SettingsApp.menu = choiceMenu
            Component.onDestruction: if (SettingsApp.menu === choiceMenu) SettingsApp.menu = null
        }

        // Na wierzchu całego okna, nie na stronie: przełączenie strony
        // w trakcie odliczania nie może go schować.
        MonitorConfirm {
            anchors.fill: parent
        }
    }

    Component {
        id: generalPage
        GeneralPage { width: pageLoader.width }
    }

    Component {
        id: monitorsPage
        MonitorsPage { width: pageLoader.width }
    }
}
