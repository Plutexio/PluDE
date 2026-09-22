pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth

// ---------------------------------------------------------------
// Stan Wi-Fi, kabla i Bluetootha dla paska. Tylko podgląd i włącz/wyłącz:
// listy sieci, hasła i parowanie są w nakładkach wyspy, które pasek
// otwiera przez IPC (IslandLink.toggleOverlay).
//
// Networking i Bluetooth ładują się asynchronicznie (w wyspie zmierzone
// 1–6 s): do tego czasu brak urządzeń i adaptera, więc wszystko znosi null.
// ---------------------------------------------------------------
Singleton {
    id: root

    // ---- sieć ----

    function deviceOf(type) {
        const all = Networking.devices.values;
        for (let i = 0; i < all.length; i++) if (all[i].type === type) return all[i];
        return null;
    }

    readonly property var wifiDevice: deviceOf(DeviceType.Wifi)
    readonly property var wiredDevice: deviceOf(DeviceType.Wired)

    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var wifiNetwork: {
        if (!wifiDevice) return null;
        const n = wifiDevice.networks.values;
        for (let i = 0; i < n.length; i++) if (n[i].connected) return n[i];
        return null;
    }
    readonly property real wifiStrength: wifiNetwork ? wifiNetwork.signalStrength : 0
    readonly property bool wiredConnected: wiredDevice !== null && wiredDevice.connected

    // Portal albo brak internetu przy połączonej sieci — kropka ostrzeżenia.
    readonly property bool limited: Networking.connectivity === NetworkConnectivity.Portal
        || Networking.connectivity === NetworkConnectivity.Limited

    readonly property string netIcon: wiredConnected && !wifiNetwork ? "wired"
        : !wifiEnabled ? "wifiOff"
        : !wifiNetwork ? "wifiOff"
        : wifiStrength >= 0.67 ? "wifi"
        : wifiStrength >= 0.34 ? "wifi2" : "wifi1"

    readonly property string netLabel: wiredConnected && !wifiNetwork ? "Kabel"
        : !wifiEnabled ? "Wi-Fi wyłączone"
        : wifiNetwork ? wifiNetwork.name
        : "Brak połączenia"

    function setWifiEnabled(on) { Networking.wifiEnabled = on; }

    // ---- Bluetooth ----

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btEnabled: adapter !== null && adapter.enabled
    readonly property var btConnected: {
        const all = Bluetooth.devices.values;
        const out = [];
        for (let i = 0; i < all.length; i++) if (all[i].connected) out.push(all[i]);
        return out;
    }

    readonly property string btIcon: !btEnabled ? "bluetoothOff"
        : btConnected.length > 0 ? "bluetoothConnected" : "bluetooth"

    readonly property string btLabel: adapter === null ? "Bluetooth niedostępny"
        : !btEnabled ? "Bluetooth wyłączony"
        : btConnected.length === 0 ? "Bluetooth: brak połączeń"
        : btConnected.map(d => d.name || d.deviceName || d.address).join(", ")

    // Jak BluetoothService wyspy: wyłączony Bluetooth to blokada rfkill,
    // a zablokowany adapter ignoruje enabled = true. Włączanie przez
    // rfkill unblock (bez roota), wyłączanie przez enabled = false + block,
    // żeby wyspa i aplet KDE widziały ten sam stan.
    function setBtEnabled(on) {
        if (on) {
            rfkill.command = ["rfkill", "unblock", "bluetooth"];
            rfkill.running = true;
            if (adapter && adapter.state !== BluetoothAdapterState.Blocked) adapter.enabled = true;
        } else {
            if (adapter) adapter.enabled = false;
            rfkill.command = ["rfkill", "block", "bluetooth"];
            rfkill.running = true;
        }
    }

    Process { id: rfkill }
}
