import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Common
import qs.PluLauncher

// Dock na monitorach innych niż monitor docka: przycisk launchera i okna
// z obszarów roboczych TEGO monitora, pogrupowane po aplikacji. Bez
// przypiętych, powiększania i przeciągania: to podgląd, co tu jest otwarte.
// Launcher otwiera się na tym monitorze (LauncherService.toggleOn).
//
// Kropka pod ikoną = okno. Jasna: na bieżącym obszarze tego monitora,
// blada: na innym jego obszarze, akcent: okno z fokusem.
//
// Klik: okno aplikacji z fokusem (najpierw z bieżącego obszaru); jeśli ta
// aplikacja już ma fokus, następne jej okno na tym monitorze. Kółko: to
// samo w obie strony. Środkowy: nowe okno. Prawy: lista okien tej aplikacji
// na tym monitorze (bez reszty menu dużego docka).
//
// Chowanie jak w dużym docku (pasek przy krawędzi, pusty obszar trzyma go
// na widoku, pełny ekran chowa) i z tą samą jedną MouseArea na całość:
// MouseArea na każdej ikonie kradłaby hover i dock chowałby się pod kursorem.
PanelWindow {
    id: root

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    // Wymiary jak w dużym docku (Dock.qml): ten sam dock, tylko mniej w nim.
    property int iconSize: 54
    property int cellWidth: iconSize + 12
    property int separatorWidth: 14
    property int dockPadding: 6
    property int dockHeight: iconSize + 22
    property int dockRadius: 26
    property int bottomMargin: 8
    property int headroom: 40           // nad dockiem: podpowiedź
    property int maxDots: 3

    property int revealHeight: 2
    property int revealDelay: 120
    property int hideDelay: 450
    property int wheelStepDelta: 120

    // ---------------------------------------------------------------
    // Okno
    // ---------------------------------------------------------------

    anchors {
        bottom: true
        left: true
        right: true
    }

    implicitHeight: headroom + dockHeight + bottomMargin
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "plude-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property int dockTop: headroom

    mask: Region {
        x: body.x
        width: body.width
        y: root.shown ? root.dockTop : root.height - root.revealHeight
        height: root.shown ? root.dockHeight + root.bottomMargin : root.revealHeight
    }

    // ---------------------------------------------------------------
    // Okna tego monitora
    // ---------------------------------------------------------------

    readonly property var hyprMonitor: Hyprland.monitorFor(root.screen)
    readonly property var workspace: hyprMonitor ? hyprMonitor.activeWorkspace : null

    function appIdOf(t) {
        if (t.wayland) return t.wayland.appId;
        return t.lastIpcObject ? (t.lastIpcObject["class"] || "") : "";
    }

    // { klucz: [okna] } i kolejność kluczy (jak pojawiały się okna).
    // Zwykłe obszary (id > 0): okna ze scratchpada nie są „na tym monitorze”.
    readonly property var groups: {
        DockService.appIdRevision;
        Apps.appCount;
        const all = Hyprland.toplevels.values;
        const g = {};
        const order = [];
        for (let i = 0; i < all.length; i++) {
            const t = all[i];
            const ws = t.workspace;
            if (!ws || ws.id <= 0 || !hyprMonitor || ws.monitor !== hyprMonitor) continue;
            const k = DockService.keyForAppId(appIdOf(t));
            if (!g[k]) { g[k] = []; order.push(k); }
            g[k].push(t);
        }
        return { byKey: g, keys: order };
    }

    readonly property var keys: groups.keys
    // Rząd jak w dużym docku: launcher | separator | okna.
    readonly property var items: keys.length > 0
        ? [DockService.launcherKey, DockService.separatorKey].concat(keys)
        : [DockService.launcherKey]
    function windowsFor(key) { return groups.byKey[key] || []; }

    function onCurrent(t) { return workspace !== null && t.workspace === workspace; }

    // Okno z fokusem przez Wayland (activate), a gdy uchwytu jeszcze nie ma,
    // przez Hyprlanda po adresie.
    function focusWindow(t) {
        if (t.wayland) t.wayland.activate();
        else Hyprland.dispatch("hl.dsp.focus({ window = \"address:0x" + t.address + "\" })");
    }

    function activate(key, step) {
        const wins = windowsFor(key);
        if (wins.length === 0) return;
        const cur = wins.findIndex(t => t.activated);
        if (cur < 0) {
            // Najpierw okno z bieżącego obszaru: nie przerzucamy widoku bez potrzeby.
            const here = wins.filter(onCurrent);
            focusWindow(here.length > 0 ? here[0] : wins[0]);
        } else if (wins.length > 1) {
            focusWindow(wins[(cur + step + wins.length) % wins.length]);
        }
    }

    // ---------------------------------------------------------------
    // Kiedy widać
    // ---------------------------------------------------------------

    readonly property bool fullscreen: workspace !== null && workspace.hasFullscreen
    readonly property bool emptyWorkspace: workspace !== null && workspace.toplevels.values.length === 0
    readonly property bool pointerInside: hitArea.containsMouse

    property bool revealed: false
    readonly property bool menuOpen: menu.visible
    readonly property bool shown: !fullscreen && (revealed || emptyWorkspace || menuOpen)

    onShownChanged: {
        bodyShow.stop();
        bodyHide.stop();
        if (shown) bodyShow.start(); else bodyHide.start();
    }

    onPointerInsideChanged: {
        if (pointerInside) {
            hideTimer.stop();
            if (shown) revealed = true; else revealTimer.restart();
        } else {
            revealTimer.stop();
            hideTimer.restart();
        }
    }

    Timer {
        id: revealTimer
        interval: root.revealDelay
        onTriggered: if (root.pointerInside) root.revealed = true
    }

    Timer {
        id: hideTimer
        interval: root.hideDelay
        onTriggered: if (!root.pointerInside && !root.menuOpen) root.revealed = false
    }

    // Menu zamknięte kliknięciem w oknie aplikacji: kursora nad dockiem nie
    // ma, więc chowamy go jak po zjechaniu.
    onMenuOpenChanged: if (!menuOpen && !pointerInside) hideTimer.restart()

    // ---------------------------------------------------------------
    // Model rzędu
    // ---------------------------------------------------------------
    //
    // ListModel synchronizowany ruchami jak w dużym docku: tablica wprost
    // w Repeaterze tworzyłaby delegaty od nowa przy każdym nowym oknie.

    ListModel { id: rowModel }

    function syncModel(list) {
        for (let i = rowModel.count - 1; i >= 0; i--)
            if (list.indexOf(rowModel.get(i).key) < 0) rowModel.remove(i);
        for (let i = 0; i < list.length; i++) {
            if (i < rowModel.count && rowModel.get(i).key === list[i]) continue;
            let from = -1;
            for (let j = i + 1; j < rowModel.count; j++)
                if (rowModel.get(j).key === list[i]) { from = j; break; }
            if (from >= 0) rowModel.move(from, i, 1);
            else rowModel.insert(i, { key: list[i] });
        }
    }

    onItemsChanged: syncModel(items)
    Component.onCompleted: {
        syncModel(items);
        if (shown) body.open = 1;
    }

    // ---------------------------------------------------------------
    // Dock
    // ---------------------------------------------------------------

    Rectangle {
        id: body

        width: row.implicitWidth + root.dockPadding * 2
        height: root.dockHeight
        x: Math.round((root.width - width) / 2)

        // Jedna wartość na pozycję, zwężenie i krycie, jak w dużym docku.
        property real open: 0
        y: root.dockTop + (1 - open) * (root.height - root.dockTop + 2)
        opacity: 0.4 + 0.6 * Math.min(1, open)
        transform: Scale {
            origin.x: body.width / 2
            origin.y: body.height
            xScale: 0.8 + 0.2 * body.open
        }

        radius: root.dockRadius
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        Behavior on width {
            NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot }
        }

        NumberAnimation {
            id: bodyShow
            target: body; property: "open"; to: 1
            duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.8
        }
        NumberAnimation {
            id: bodyHide
            target: body; property: "open"; to: 0
            duration: 260; easing.type: Easing.InBack; easing.overshoot: 1.2
        }

        Row {
            id: row
            x: root.dockPadding
            height: parent.height

            Repeater {
                model: rowModel

                Item {
                    id: cell

                    required property string key
                    readonly property bool isLauncher: key === DockService.launcherKey
                    readonly property bool isSeparator: key === DockService.separatorKey
                    readonly property bool isApp: !isLauncher && !isSeparator
                    readonly property var windows: root.windowsFor(key)
                    readonly property int unseen: isApp && !key.startsWith("wm:") ? DockService.unseenCount(key) : 0
                    readonly property bool hovered: root.hoveredKey === key

                    width: isSeparator ? root.separatorWidth : root.cellWidth
                    height: row.height

                    // Separator jak w DockItem.
                    Rectangle {
                        visible: cell.isSeparator
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -3
                        width: 1
                        height: Math.round(root.iconSize * 0.7)
                        color: Qt.rgba(1, 1, 1, 0.14)
                    }

                    // Podświetlenie pod kursorem jak w DockItem.
                    Rectangle {
                        visible: !cell.isSeparator
                        anchors.centerIn: icon
                        width: root.iconSize + 8
                        height: root.iconSize + 8
                        radius: Math.round(root.iconSize * 0.3)
                        color: hitArea.pressed ? Theme.hoverStrong : Theme.hover
                        opacity: cell.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
                    }

                    Image {
                        id: icon
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: (root.dockHeight - root.iconSize) / 2 - 3
                        width: root.iconSize
                        height: root.iconSize
                        visible: cell.isApp
                        source: cell.isApp ? DockService.iconFor(cell.key) : ""
                        sourceSize: Qt.size(root.iconSize, root.iconSize)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: false   // image://icon nie jest wątkowo bezpieczny
                        smooth: true
                        mipmap: true
                        scale: cell.hovered ? (hitArea.pressed ? 1.02 : 1.06) : 1
                        Behavior on scale { NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

                        // Wskakiwanie nowej ikony.
                        opacity: 0
                        Component.onCompleted: appear.start()
                        NumberAnimation { id: appear; target: icon; property: "opacity"; to: 1; duration: Theme.fadeMs }

                        // Plakietka powiadomień, jak w dużym docku.
                        Rectangle {
                            visible: cell.unseen > 0
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -4
                            anchors.topMargin: -3
                            width: Math.max(15, badgeText.implicitWidth + 8)
                            height: 15
                            radius: height / 2
                            color: Theme.danger

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: cell.unseen > 9 ? "9+" : String(cell.unseen)
                                color: Theme.text
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }

                    // Launcher: siatka 3×3 kropek jak w DockItem.
                    Grid {
                        visible: cell.isLauncher
                        anchors.centerIn: icon
                        columns: 3
                        spacing: dot
                        readonly property int dot: Math.round(root.iconSize / 7)
                        scale: icon.scale
                        Repeater {
                            model: 9
                            Rectangle { width: parent.dot; height: parent.dot; radius: width / 2; color: Theme.text }
                        }
                    }

                    // Kropki okien.
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.dockHeight - 8
                        spacing: 3

                        Repeater {
                            model: Math.min(root.maxDots, cell.windows.length)

                            Rectangle {
                                required property int index
                                readonly property var win: cell.windows[index] || null

                                width: 4
                                height: 4
                                radius: 2
                                color: win && win.activated ? Theme.accent
                                     : win && root.onCurrent(win) ? Theme.text
                                     : Theme.textFaint
                                Behavior on color { ColorAnimation { duration: Theme.fadeMs } }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // Podpowiedź
    // ---------------------------------------------------------------

    function windowsLabel(n) {
        return n === 1 ? "1 okno" : n + (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14) ? " okna" : " okien");
    }

    Rectangle {
        id: tooltip

        readonly property Item target: root.itemFor(root.hoveredKey)
        readonly property bool wanted: root.shown && target !== null && !target.isSeparator && !root.menuOpen

        width: tipText.implicitWidth + 20
        height: 26
        radius: 13
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        // Pozycja zapamiętana: gasnąca podpowiedź zostaje, gdzie była.
        property real cx: 0
        onTargetChanged: if (target) cx = body.x + row.x + target.x + target.width / 2
        x: Math.round(Math.max(4, Math.min(root.width - width - 4, cx - width / 2)))
        y: root.dockTop - height - 4

        opacity: wanted ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }

        Text {
            id: tipText
            anchors.centerIn: parent
            color: Theme.text
            font.pixelSize: 12
            text: {
                const t = tooltip.target;
                if (!t) return "";
                const n = t.windows.length;
                return DockService.nameFor(t.key) + (n > 1 ? " · " + root.windowsLabel(n) : "");
            }
        }
    }

    // ---------------------------------------------------------------
    // Lista okien (prawy przycisk)
    // ---------------------------------------------------------------

    PopupMenu { id: menu }

    function openWindowList(key) {
        const it = itemFor(key);
        const wins = windowsFor(key);
        if (!it || wins.length === 0) return;
        const out = [{ header: DockService.nameFor(key) }];
        for (let i = 0; i < wins.length; i++) {
            const t = wins[i];
            out.push({
                text: t.title !== "" ? t.title : DockService.nameFor(key),
                checked: t.activated,
                run: () => root.focusWindow(t)
            });
        }
        const p = it.mapToItem(root.contentItem, it.width / 2, 0);
        menu.openAt(root, p.x, root.dockTop - 6, out);
    }

    // ---------------------------------------------------------------
    // Mysz
    // ---------------------------------------------------------------

    property string hoveredKey: ""

    function itemFor(key) {
        if (key === "") return null;
        for (let i = 0; i < row.children.length; i++) {
            const c = row.children[i];
            if (c.key === key) return c;
        }
        return null;
    }

    function keyAt(mx, my) {
        if (!shown || my < root.dockTop) return "";
        const c = row.childAt(mx - body.x - row.x, row.height / 2);
        return c && c.key !== undefined ? c.key : "";
    }

    MouseArea {
        id: hitArea

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        property real wheelAccum: 0

        onPositionChanged: mouse => root.hoveredKey = root.keyAt(mouse.x, mouse.y)
        onContainsMouseChanged: if (!containsMouse) root.hoveredKey = ""

        onClicked: mouse => {
            const key = root.keyAt(mouse.x, mouse.y);
            if (key === "") return;
            if (key === DockService.separatorKey) return;
            if (key === DockService.launcherKey) {
                if (mouse.button === Qt.LeftButton) LauncherService.toggleOn(root.screen);
            } else if (mouse.button === Qt.MiddleButton) DockService.launch(key);
            else if (mouse.button === Qt.RightButton) root.openWindowList(key);
            else root.activate(key, 1);
        }

        onWheel: wheel => {
            const key = root.keyAt(wheel.x, wheel.y);
            if (key === "") return;
            wheelAccum += wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x;
            const n = Math.trunc(wheelAccum / root.wheelStepDelta);
            if (n === 0) return;
            wheelAccum -= n * root.wheelStepDelta;
            root.activate(key, n < 0 ? 1 : -1);
        }
    }
}
