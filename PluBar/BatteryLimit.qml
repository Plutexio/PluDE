pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// ---------------------------------------------------------------
// Limit ładowania baterii (charge_control_end_threshold).
//
// Zapis prosto do /sys/class/power_supply/BAT*/. Pliki należą do roota,
// grupie wheel zapis daje reguła udev obok (99-plude-battery.rules,
// instalacja jednorazowa). Bez niej suwak jest wygaszony z podpowiedzią.
//
// UPower (to, czym GNOME ustawił 80%) umie tylko włączyć swój stały próg
// 75/80 albo go wyłączyć, i po starcie systemu wpisuje go z powrotem,
// jeśli był włączony. Dlatego przed własnym zapisem wyłączamy jego próg
// (EnableChargeThreshold false, polkit pozwala aktywnej sesji bez hasła),
// a wybraną wartość trzymamy w settings.json i przy starcie powłoki
// wpisujemy ją ponownie, gdyby coś ją zmieniło.
//
// Start ładowania = limit − hysteresis (jak 75/80 w UPower): bateria nie
// dobija co chwilę od 79 do 80%. 100% = bez limitu: tryb Standard, jeśli
// sterownik ma charge_types (Dell), inaczej sam próg 100.
//
// sysfs nie zgłasza zmian przez inotify, więc odczyt przy otwarciu panelu
// (refresh) i po każdym zapisie.
// ---------------------------------------------------------------
Singleton {
    id: root

    // Dell przyjmuje koniec 55–100 i start 50–95, start co najmniej 5 niżej.
    property int minimum: 55
    property int maximum: 100
    property int step: 5
    property int hysteresis: 5
    // Przeciąganie przechodzi przez kilka pozycji; zapis idzie dopiero,
    // gdy suwak postoi tyle ms (ostatnia wartość wygrywa).
    property int writeDelayMs: 350

    // Katalog baterii z progiem, np. /sys/class/power_supply/BAT0. Pusto =
    // sterownik nie umie limitu i sekcja w panelu znika.
    property string battery: ""
    property bool writable: false
    readonly property bool supported: battery !== ""

    // Limit w %, 100 = bez limitu. -1 dopóki nie ma odczytu.
    property int limit: -1
    // Aktywny tryb z charge_types ("Custom", "Standard", "Adaptive"…), pusto
    // gdy sterownik go nie ma.
    property string chargeType: ""
    property string error: ""

    function refresh() {
        probe.running = true;
    }

    function set(value) {
        if (!supported || !writable) return;
        const v = Math.max(minimum, Math.min(maximum, Math.round(value / step) * step));
        if (v === limit && !writeTimer.running) return;
        limit = v;
        error = "";
        writeTimer.restart();
    }

    // Klik w ikonę suwaka: bez limitu i z powrotem do poprzedniego.
    property int previous: 80
    function toggle() {
        if (limit < maximum) { previous = limit; set(maximum); }
        else set(previous);
    }

    Timer {
        id: writeTimer
        interval: root.writeDelayMs
        onTriggered: root.write(root.limit)
    }

    function write(value) {
        Settings.set("batteryLimit", value);
        writer.command = ["sh", "-c", writeScript, "plude-battery", battery, String(value),
                          String(value - hysteresis), String(maximum)];
        writer.running = true;
    }

    // Backticki, bo wiele linii; \${ to ${ powłoki, nie wstawka JS.
    // $1 katalog baterii, $2 koniec, $3 start, $4 maksimum (bez limitu).
    // Kolejność progów: koniec musi zostać nad startem po KAŻDYM zapisie,
    // inaczej sterownik odrzuca wartość (75/80 → 85/90 najpierw koniec,
    // 75/80 → 55/60 najpierw start).
    readonly property string writeScript: `
        d=$1; end=$2; start=$3; max=$4
        dev=/org/freedesktop/UPower/devices/battery_$(basename "$d")
        if busctl get-property org.freedesktop.UPower "$dev" org.freedesktop.UPower.Device \
                ChargeThresholdEnabled 2>/dev/null | grep -q true; then
            busctl call org.freedesktop.UPower "$dev" org.freedesktop.UPower.Device \
                EnableChargeThreshold b false || exit 1
        fi
        set -e
        if [ "$end" -ge "$max" ]; then
            if grep -qw Standard "$d/charge_types" 2>/dev/null; then
                echo Standard > "$d/charge_types"
            else
                echo "$max" > "$d/charge_control_end_threshold"
            fi
            exit 0
        fi
        if [ "$end" -gt "$(cat "$d/charge_control_start_threshold")" ]; then
            echo "$end" > "$d/charge_control_end_threshold"
            echo "$start" > "$d/charge_control_start_threshold"
        else
            echo "$start" > "$d/charge_control_start_threshold"
            echo "$end" > "$d/charge_control_end_threshold"
        fi
        if grep -qw Custom "$d/charge_types" 2>/dev/null; then
            echo Custom > "$d/charge_types"
        fi`

    Process {
        id: writer
        stderr: StdioCollector { id: writerErr }
        onExited: code => {
            if (code !== 0) {
                root.error = "Nie udało się zapisać limitu";
                console.warn("BatteryLimit: zapis " + root.limit + "% nie wyszedł: " + writerErr.text.trim());
            }
            root.refresh();
        }
    }

    // ---- odczyt ----

    // Jedna linia: katalog, zapisywalność, koniec, aktywny tryb.
    // [Custom] w charge_types to tryb wybrany.
    Process {
        id: probe
        command: ["sh", "-c", `
            for f in /sys/class/power_supply/*/charge_control_end_threshold; do
                [ -e "$f" ] || exit 0
                d=\${f%/*}
                w=0; [ -w "$f" ] && [ -w "$d/charge_control_start_threshold" ] && w=1
                t=$(grep -o "\\[[A-Za-z]*\\]" "$d/charge_types" 2>/dev/null | tr -d "[]")
                echo "$d $w $(cat "$f") $t"
                exit 0
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(" ");
                if (f.length < 3) { root.battery = ""; return; }
                root.battery = f[0];
                root.writable = f[1] === "1";
                root.chargeType = f[3] || "";
                // Zapis czeka: odczyt sprzed niego cofnąłby suwak pod palcem.
                if (writeTimer.running || writer.running) return;
                const end = parseInt(f[2]) || root.maximum;
                // Poza Custom sterownik ignoruje progi (Standard ładuje do pełna).
                root.limit = root.chargeType === "" || root.chargeType === "Custom" ? end : root.maximum;
                root.restoreSaved();
            }
        }
    }

    // Raz po starcie: wartość z settings.json wygrywa z tym, co zastaliśmy
    // (UPower po starcie systemu wpisuje swoje 80%). 0 = nigdy nie ustawiano
    // z PluDE, wtedy nic nie ruszamy.
    property bool restored: false
    function restoreSaved() {
        if (restored || !Settings.loaded || limit < 0) return;
        restored = true;
        const saved = Settings.batteryLimit;
        if (saved > 0 && saved !== limit && writable) {
            console.info("BatteryLimit: przywracam " + saved + "% (było " + limit + "%)");
            limit = saved;
            write(saved);
        }
    }

    Connections {
        target: Settings
        function onLoadedChanged() { root.restoreSaved(); }
    }

    Component.onCompleted: refresh()
}
