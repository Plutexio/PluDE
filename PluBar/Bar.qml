import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import qs.Common

// Pasek u góry ekranu: dwie pigułki po bokach, wyspa między nimi.
//
//   [obszary robocze · zasobnik]      ( wyspa )      [jasność · dźwięk · mikrofon ·
//                                                     sieć · BT · energia · bateria · zasilanie]
//
// Pigułki mają wysokość i odstęp od góry zwiniętej wyspy, więc stoją z nią
// w jednej linii. Każda sięga najwyżej do sideLimit: rozwinięta wyspa
// (nakładka 620 px) mieści się między nimi z zapasem islandGap.
//
// Wi-Fi i Bluetooth nie mają tu własnych list: klik otwiera nakładkę wyspy
// (IslandLink.toggleOverlay), gdzie są sieci, hasła i parowanie.
PanelWindow {
    id: root

    // ---------------------------------------------------------------
    // Ustawienia
    // ---------------------------------------------------------------

    // Jak zwinięta wyspa (collapsedHeight, topMargin w DynamicIsland.qml).
    property int barHeight: 34
    property int topMargin: 8
    property int edgeMargin: 8          // od bocznej krawędzi ekranu
    property int pillPadding: 2         // między krawędzią pigułki a kontrolką
    property int controlSize: 30        // parzyste: barHeight − 2 × pillPadding

    // Szerokość, którą zajmuje wyspa w najszerszym stanie (overlayWidth
    // nakładek w wyspie) i odstęp od niej. Zmienisz nakładkę tam → tutaj też.
    property int islandMaxWidth: 620
    property int islandGap: 16

    property int workspaceMin: 5        // tyle kropek obszarów roboczych zawsze
    property int tipDelay: 450          // ms najechania, zanim wyjdzie podpowiedź
    property int tipGap: 6
    // Wskakiwanie kontrolek: co tyle ms, od wyspy na zewnątrz.
    property int appearStagger: 40

    // ---------------------------------------------------------------
    // Okno
    // ---------------------------------------------------------------

    screen: Settings.screen

    anchors {
        top: true
        left: true
        right: true
    }

    // Stała wysokość: pod pigułkami jest miejsce na podpowiedź (dwie linie).
    // Poza pigułkami okno nie łapie myszy (maska), więc nie zasłania okien.
    implicitHeight: topMargin + barHeight + tipGap + 44
    color: "transparent"

    // Pasek rezerwuje miejsce (okna zaczynają się pod nim), chyba że
    // ustawienia mówią inaczej. Schowany razem z wyspą oddaje je oknom.
    exclusionMode: Settings.barReserve ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: hiddenWithIsland ? 0 : topMargin + barHeight

    WlrLayershell.namespace: "plude-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        Region { item: leftPill }
        Region { item: rightPill }
    }

    // ---------------------------------------------------------------
    // Kiedy pasek jest widoczny
    // ---------------------------------------------------------------

    readonly property var hyprMonitor: Hyprland.monitorFor(root.screen)
    readonly property var workspace: hyprMonitor ? hyprMonitor.activeWorkspace : null
    readonly property bool fullscreen: workspace !== null && workspace.hasFullscreen
    readonly property bool hiddenWithIsland: Settings.hideWithIsland && IslandLink.islandHidden
    readonly property bool shown: !fullscreen && !hiddenWithIsland

    // Jedna wartość na pozycję i krycie obu pigułek (DESIGN.md: wszystko
    // z jednej wartości, żeby odbicie obejmowało je naraz).
    property real open: 0

    onShownChanged: {
        showAnim.stop();
        hideAnim.stop();
        if (shown) showAnim.start(); else hideAnim.start();
        if (!shown) { menu.close(); volumePanel.visible = false; brightnessPanel.visible = false; }
    }
    Component.onCompleted: if (shown) showAnim.start()

    NumberAnimation {
        id: showAnim
        target: root; property: "open"; to: 1
        duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.8
    }
    NumberAnimation {
        id: hideAnim
        target: root; property: "open"; to: 0
        duration: 200; easing.type: Easing.InCubic
    }

    readonly property real pillY: topMargin - (1 - open) * (barHeight + topMargin + 4)
    readonly property int sideLimit: Math.floor((width - islandMaxWidth) / 2) - islandGap - edgeMargin

    // ---------------------------------------------------------------
    // Podpowiedź
    // ---------------------------------------------------------------
    //
    // Kontrolka zgłasza najechanie (noteHover), a pasek pokazuje jedną
    // wspólną podpowiedź pod nią. Po przejściu na sąsiednią kontrolkę przy
    // widocznej podpowiedzi zmiana jest od razu, bez ponownego czekania.

    property Item tipTarget: null
    property bool tipVisible: false

    function noteHover(item, on) {
        if (on) {
            tipTarget = item;
            placeTip();
            if (!tipVisible) tipTimer.restart();
        } else if (tipTarget === item) {
            tipTimer.stop();
            tipVisible = false;
        }
    }

    // Kółko i klik: pokaż od razu, z aktualną wartością.
    function poke(item) {
        tipTarget = item;
        placeTip();
        tipTimer.stop();
        tipVisible = true;
    }

    function hideTip() {
        tipTimer.stop();
        tipVisible = false;
    }

    // mapToItem nie jest powiązaniem, więc pozycję liczymy przy zmianie celu.
    property real tipCenter: 0
    function placeTip() {
        if (!tipTarget) return;
        tipCenter = tipTarget.mapToItem(root.contentItem, tipTarget.width / 2, 0).x;
    }

    Timer {
        id: tipTimer
        interval: root.tipDelay
        onTriggered: if (root.tipTarget && root.tipTarget.hovered) root.tipVisible = true
    }

    // Punkt pod kontrolką, od którego rosną panele i menu.
    function below(item) {
        const p = item.mapToItem(root.contentItem, item.width / 2, item.height);
        return { x: p.x, y: root.topMargin + root.barHeight + 6 };
    }

    // ---------------------------------------------------------------
    // Lewa pigułka: obszary robocze i zasobnik
    // ---------------------------------------------------------------

    // { id: HyprlandWorkspace } dla zwykłych obszarów tego monitora. Repeater
    // stoi na LICZBIE kropek, nie na tablicy: tablica tworzyłaby delegaty od
    // nowa przy każdym nowym obszarze i przejście kropki nie miałoby czego animować.
    readonly property var workspaceById: {
        const all = Hyprland.workspaces.values;
        const out = {};
        for (let i = 0; i < all.length; i++) {
            const w = all[i];
            if (w.id <= 0) continue;   // specjalne (scratchpad) mają ujemne id
            if (hyprMonitor && w.monitor && w.monitor !== hyprMonitor) continue;
            out[w.id] = w;
        }
        return out;
    }
    readonly property int workspaceCount: {
        let n = workspaceMin;
        for (const id in workspaceById) n = Math.max(n, parseInt(id));
        if (workspace) n = Math.max(n, workspace.id);
        return n;
    }

    function focusWorkspace(target) {
        // Hyprland w Lua: dispatch przyjmuje wywołanie hl.dsp, jak binds w hyprland.lua.
        // Liczba = id obszaru, napis = selektor ("e+1": następny istniejący).
        const sel = typeof target === "number" ? String(target) : JSON.stringify(target);
        Hyprland.dispatch("hl.dsp.focus({ workspace = " + sel + " })");
    }

    ClippingRectangle {
        id: leftPill

        x: root.edgeMargin
        y: root.pillY
        opacity: Math.min(1, root.open)
        height: root.barHeight
        width: Math.min(root.sideLimit, Math.ceil(leftRow.implicitWidth) + root.pillPadding * 2)
        radius: height / 2
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        contentUnderBorder: true

        Behavior on width {
            NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot }
        }

        Row {
            id: leftRow
            x: root.pillPadding
            y: root.pillPadding
            height: root.controlSize

            // ---- obszary robocze ----
            Item {
                id: workspaces
                width: wsRow.implicitWidth + 16
                height: root.controlSize

                // Kółko nad kropkami: sąsiedni obszar (e±1 = tylko istniejące).
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    property real acc: 0
                    onWheel: event => {
                        acc += event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
                        const n = Math.trunc(acc / 120);
                        if (n === 0) return;
                        acc -= n * 120;
                        root.focusWorkspace(n < 0 ? "e+1" : "e-1");
                    }
                }

                Row {
                    id: wsRow
                    anchors.centerIn: parent

                    Repeater {
                        model: root.workspaceCount

                        Item {
                            id: slot
                            required property int index

                            readonly property int wsId: index + 1
                            readonly property var ws: root.workspaceById[wsId] || null
                            readonly property bool current: root.workspace !== null && root.workspace.id === wsId
                            readonly property int windows: ws ? ws.toplevels.values.length : 0
                            readonly property bool urgent: ws !== null && ws.urgent
                            readonly property bool hovered: slotMouse.containsMouse

                            readonly property string tip: "Obszar " + wsId
                                + (windows === 0 ? " · pusty"
                                   : windows === 1 ? " · 1 okno"
                                   : " · " + windows + (windows < 5 ? " okna" : " okien"))
                            readonly property string hint: "SUPER+" + (wsId % 10)

                            width: dot.width + 8
                            height: root.controlSize

                            Rectangle {
                                id: dot
                                anchors.centerIn: parent
                                width: slot.current ? 20 : 8
                                height: 8
                                radius: 4
                                // Pełne kolory: zajęty jaśniej, pusty jak obrys.
                                color: slot.urgent ? Theme.warning
                                     : slot.current ? Theme.accent
                                     : slot.windows > 0 ? Theme.textDim
                                     : "#2a2a2c"
                                scale: slot.hovered && !slot.current ? 1.3 : 1

                                Behavior on width {
                                    NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                                }
                                Behavior on color { ColorAnimation { duration: Theme.fadeMs } }
                                Behavior on scale { NumberAnimation { duration: Theme.quickMs } }
                            }

                            MouseArea {
                                id: slotMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onContainsMouseChanged: root.noteHover(slot, containsMouse)
                                onClicked: {
                                    root.hideTip();
                                    root.focusWorkspace(slot.wsId);
                                }
                            }
                        }
                    }
                }
            }

            // ---- zasobnik ----
            Rectangle {
                visible: tray.count > 0
                width: 9
                height: root.controlSize
                color: "transparent"
                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 14
                    color: Theme.border
                }
            }

            Repeater {
                id: tray
                model: SystemTray.items

                BarButton {
                    id: trayButton
                    required property var modelData
                    required property int index

                    bar: root
                    size: root.controlSize
                    shown: root.shown
                    delay: 120 + index * root.appearStagger
                    tip: modelData.tooltipTitle || modelData.title || modelData.id
                    hint: modelData.tooltipDescription || ""

                    Image {
                        width: 16
                        height: 16
                        source: trayButton.modelData.icon
                        sourceSize: Qt.size(16, 16)
                        asynchronous: false   // image://icon nie jest wątkowo bezpieczny
                        smooth: true
                    }

                    function showMenu() {
                        const p = mapToItem(root.contentItem, 0, height + 6);
                        modelData.display(root, Math.round(p.x), Math.round(p.y));
                    }

                    onClicked: {
                        root.hideTip();
                        if (modelData.onlyMenu && modelData.hasMenu) showMenu();
                        else modelData.activate();
                    }
                    onRightClicked: {
                        root.hideTip();
                        if (modelData.hasMenu) showMenu(); else modelData.secondaryActivate();
                    }
                    onMiddleClicked: modelData.secondaryActivate()
                    onStepped: steps => modelData.scroll(steps * 120, false)
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // Prawa pigułka: kontrolki systemu
    // ---------------------------------------------------------------

    function pct(v) { return Math.round(v * 100) + "%"; }

    function duration(sec) {
        if (!sec || sec <= 0) return "";
        const h = Math.floor(sec / 3600);
        const m = Math.round((sec % 3600) / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.ready && battery.isLaptopBattery
    readonly property bool charging: hasBattery
        && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged
            || battery.state === UPowerDeviceState.PendingCharge)

    readonly property string batteryState: {
        if (!hasBattery) return "";
        switch (battery.state) {
        case UPowerDeviceState.Charging:
            return "ładowanie" + (battery.timeToFull > 0 ? ", pełna za " + duration(battery.timeToFull) : "");
        case UPowerDeviceState.FullyCharged: return "naładowana";
        case UPowerDeviceState.PendingCharge: return "podłączona, nie ładuje";
        case UPowerDeviceState.Discharging:
            return battery.timeToEmpty > 0 ? "zostało " + duration(battery.timeToEmpty) : "na baterii";
        default: return "";
        }
    }

    readonly property var profileNames: ({
        [PowerProfile.PowerSaver]: "Oszczędzanie energii",
        [PowerProfile.Balanced]: "Zrównoważony",
        [PowerProfile.Performance]: "Wydajność"
    })

    function openProfileMenu(item) {
        if (menu.recentlyClosed()) return;
        const p = below(item);
        const list = [{ header: "Tryb energii" }];
        const all = [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance];
        for (let i = 0; i < all.length; i++) {
            const prof = all[i];
            if (prof === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile) continue;
            list.push({
                text: root.profileNames[prof],
                checked: PowerProfiles.profile === prof,
                run: () => PowerProfiles.profile = prof
            });
        }
        menu.openAt(root, p.x, p.y, list);
    }

    // Sieć / Bluetooth: wyspa żyje → jej nakładka, nie żyje → terminal.
    function openNetwork(mode) {
        if (IslandLink.alive) IslandLink.toggleOverlay(mode);
        else Quickshell.execDetached([Settings.terminal, "-e", mode === "wifi" ? "nmtui" : "bluetoothctl"]);
    }

    ClippingRectangle {
        id: rightPill

        x: root.width - root.edgeMargin - width
        y: root.pillY
        opacity: Math.min(1, root.open)
        height: root.barHeight
        width: Math.min(root.sideLimit, Math.ceil(rightRow.implicitWidth) + root.pillPadding * 2)
        radius: height / 2
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        contentUnderBorder: true

        Behavior on width {
            NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot }
        }

        // Przyklejony do prawej: kontrolka, która dochodzi (mikrofon po
        // starcie PipeWire), rozpycha pigułkę w stronę wyspy, a reszta stoi.
        Row {
            id: rightRow
            anchors.right: parent.right
            anchors.rightMargin: root.pillPadding
            y: root.pillPadding
            height: root.controlSize

            BarButton {
                id: brightness
                visible: Brightness.available
                bar: root
                size: root.controlSize
                shown: root.shown
                delay: 0 * root.appearStagger
                active: brightnessPanel.visible
                icon: "brightness"
                tip: "Jasność " + root.pct(Brightness.value)
                hint: "kółko: zmień · klik: suwak"
                onClicked: {
                    root.hideTip();
                    const p = root.below(brightness);
                    brightnessPanel.toggleAt(root, p.x, p.y);
                }
                onStepped: steps => { Brightness.stepBy(steps * Brightness.step); root.poke(brightness); }
            }

            BarButton {
                id: volume
                bar: root
                size: root.controlSize
                shown: root.shown
                delay: 1 * root.appearStagger
                active: volumePanel.visible
                icon: !Audio.ready ? "volumeOff"
                    : Audio.muted ? "volumeOff"
                    : Audio.volume <= 0.001 ? "volumeMute"
                    : Audio.volume < 0.5 ? "volumeLow" : "volume"
                iconColor: Audio.muted ? Theme.textDim : Theme.text
                tip: !Audio.ready ? "Brak wyjścia dźwięku"
                    : (Audio.muted ? "Wyciszone" : "Głośność " + root.pct(Audio.volume))
                      + " · " + Audio.sinkLabel(Audio.sink)
                hint: "kółko: zmień · klik: wyjścia · prawy: wycisz"
                onClicked: {
                    root.hideTip();
                    const p = root.below(volume);
                    volumePanel.toggleAt(root, p.x, p.y);
                }
                onRightClicked: { Audio.toggleMute(); root.poke(volume); }
                onStepped: steps => { Audio.stepBy(steps * Audio.step); root.poke(volume); }
            }

            BarButton {
                id: mic
                visible: Audio.micReady
                bar: root
                size: root.controlSize
                shown: root.shown
                delay: 2 * root.appearStagger
                icon: Audio.micOn ? "mic" : "micOff"
                iconColor: Audio.micOn ? Theme.text : Theme.danger
                tip: Audio.micOn ? "Mikrofon włączony" : "Mikrofon wyciszony"
                hint: "klik: " + (Audio.micOn ? "wycisz" : "włącz") + " (wszystkie wejścia)"
                onClicked: { Audio.setMicOn(!Audio.micOn); root.poke(mic); }
            }

            BarButton {
                id: network
                bar: root
                size: root.controlSize
                shown: root.shown
                delay: 3 * root.appearStagger
                icon: Connectivity.netIcon
                ghost: Connectivity.netIcon === "wifi2" || Connectivity.netIcon === "wifi1" ? "wifi" : ""
                iconColor: Connectivity.netIcon === "wifiOff" ? Theme.textDim : Theme.text
                dotColor: Connectivity.limited ? Theme.warning : "transparent"
                tip: Connectivity.netLabel
                     + (Connectivity.wifiNetwork ? " · " + root.pct(Connectivity.wifiStrength) : "")
                     + (Connectivity.limited ? " · bez internetu" : "")
                hint: "klik: sieci · prawy: " + (Connectivity.wifiEnabled ? "wyłącz" : "włącz") + " Wi-Fi"
                onClicked: { root.hideTip(); root.openNetwork("wifi"); }
                onRightClicked: { Connectivity.setWifiEnabled(!Connectivity.wifiEnabled); root.poke(network); }
            }

            BarButton {
                id: bluetooth
                visible: Connectivity.adapter !== null
                bar: root
                size: root.controlSize
                shown: root.shown
                delay: 4 * root.appearStagger
                icon: Connectivity.btIcon
                iconColor: Connectivity.btEnabled ? Theme.text : Theme.textDim
                tip: Connectivity.btLabel
                hint: "klik: urządzenia · prawy: " + (Connectivity.btEnabled ? "wyłącz" : "włącz")
                onClicked: { root.hideTip(); root.openNetwork("bluetooth"); }
                onRightClicked: { Connectivity.setBtEnabled(!Connectivity.btEnabled); root.poke(bluetooth); }
            }

            BarButton {
                id: profile
                bar: root
                size: root.controlSize
                shown: root.shown
                delay: 5 * root.appearStagger
                active: menu.visible
                icon: PowerProfiles.profile === PowerProfile.PowerSaver ? "powerSaver"
                    : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
                iconColor: PowerProfiles.profile === PowerProfile.PowerSaver ? Theme.success
                    : PowerProfiles.profile === PowerProfile.Performance ? Theme.warning : Theme.text
                tip: "Tryb energii: " + (root.profileNames[PowerProfiles.profile] || "?")
                hint: "klik: zmień"
                onClicked: { root.hideTip(); root.openProfileMenu(profile); }
            }

            BarButton {
                id: batteryButton
                visible: root.hasBattery
                bar: root
                size: root.controlSize
                shown: root.shown
                delay: 6 * root.appearStagger
                label: root.hasBattery ? root.pct(root.battery.percentage) : ""
                labelColor: batteryFill.color === Theme.danger ? Theme.danger : Theme.text
                tip: "Bateria " + label + (root.batteryState !== "" ? " · " + root.batteryState : "")
                hint: "klik: tryb energii"
                onClicked: { root.hideTip(); root.openProfileMenu(batteryButton); }

                // Bateria jak w iOS: obrys, wypełnienie wg poziomu, nóżka.
                Item {
                    width: 25
                    height: 12

                    Rectangle {
                        id: batteryShell
                        width: 22
                        height: 12
                        radius: 3.5
                        color: "transparent"
                        border.width: 1.2
                        border.color: Theme.textDim

                        Rectangle {
                            id: batteryFill
                            x: 2
                            y: 2
                            height: parent.height - 4
                            width: Math.max(2, (parent.width - 4) * (root.hasBattery ? root.battery.percentage : 0))
                            radius: 1.5
                            color: root.charging ? Theme.success
                                 : root.hasBattery && root.battery.percentage <= 0.2 ? Theme.danger
                                 : Theme.text
                        }

                        Icon {
                            visible: root.charging
                            anchors.centerIn: parent
                            kind: "bolt"
                            size: 11
                            color: Theme.surface
                        }
                    }

                    Rectangle {
                        x: 23
                        y: 4
                        width: 2
                        height: 4
                        radius: 1
                        color: Theme.textDim
                    }
                }
            }

            BarButton {
                id: power
                bar: root
                size: root.controlSize
                shown: root.shown
                delay: 7 * root.appearStagger
                icon: "power"
                tip: "Zasilanie"
                hint: "klik: wyloguj, uśpij, wyłącz · SUPER+M"
                onClicked: {
                    root.hideTip();
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.config/wlogout/plude-wlogout"]);
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // Podpowiedź, menu i panele
    // ---------------------------------------------------------------

    Rectangle {
        id: tip

        readonly property bool on: root.tipVisible && root.tipTarget !== null && root.open > 0.9

        width: Math.max(tipTitle.implicitWidth, tipHint.visible ? tipHint.implicitWidth : 0) + 20
        height: tipColumn.implicitHeight + 12
        x: Math.round(Math.max(root.edgeMargin,
                               Math.min(root.width - root.edgeMargin - width, root.tipCenter - width / 2)))
        y: root.topMargin + root.barHeight + root.tipGap + (on ? 0 : -4)
        radius: 13
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        opacity: on ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
        Behavior on y { NumberAnimation { duration: Theme.quickMs; easing.type: Easing.OutQuad } }
        Behavior on x { enabled: tip.visible; NumberAnimation { duration: Theme.quickMs; easing.type: Easing.OutQuad } }

        Column {
            id: tipColumn
            anchors.centerIn: parent
            spacing: 1

            Text {
                id: tipTitle
                text: root.tipTarget ? root.tipTarget.tip : ""
                color: Theme.text
                font.pixelSize: 12
            }

            Text {
                id: tipHint
                visible: text !== ""
                text: root.tipTarget ? (root.tipTarget.hint || "") : ""
                color: Theme.textFaint
                font.pixelSize: 11
            }
        }
    }

    PopupMenu {
        id: menu
        above: false
        menuWidth: 220
    }

    SliderPanel {
        id: brightnessPanel
        title: "Jasność ekranu"
        icon: "brightness"
        value: Brightness.value
        step: Brightness.step
        onMoved: v => Brightness.set(v)
    }

    SliderPanel {
        id: volumePanel
        title: "Głośność"
        icon: Audio.muted ? "volumeOff" : "volume"
        iconColor: Audio.muted ? Theme.danger : Theme.text
        value: Audio.volume
        step: Audio.step
        onMoved: v => Audio.setVolume(v)
        onIconClicked: Audio.toggleMute()

        entries: {
            const out = [{ header: "Wyjście" }];
            const s = Audio.sinks;
            for (let i = 0; i < s.length; i++) {
                const node = s[i];
                out.push({
                    text: Audio.sinkLabel(node),
                    icon: Audio.sinkIcon(node),
                    checked: node === Audio.sink,
                    run: () => Audio.selectSink(node)
                });
            }
            out.push({ header: "Wejście" });
            out.push({
                text: Audio.micOn ? "Mikrofon włączony" : "Mikrofon wyciszony",
                icon: Audio.micOn ? "mic" : "micOff",
                checked: Audio.micOn,
                run: () => Audio.setMicOn(!Audio.micOn)
            });
            return out;
        }
    }
}
