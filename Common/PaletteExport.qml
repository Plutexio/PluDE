import QtQuick
import Quickshell
import Quickshell.Io

// ---------------------------------------------------------------
// Paleta tapety poza PluDE: ramki okien Hyprlanda, hyprlock, wlogout.
//
// Wołane przy każdej nowej palecie i raz przy starcie powłoki (pliki
// mogło skasować coś innego, a generator mógł się zmienić). Bez palety
// pisze stałe kolory Theme, więc hyprlock.conf zawsze ma czego `source`.
//
// - Hyprland: hyprctl eval na żywo + plude-colors.lua, który hyprland.lua
//   dołącza przez dofile przy starcie.
// - hyprlock: zmienne hyprlanga w plude-lock-colors.conf (source
//   w hyprlock.conf, po wartościach domyślnych). Kolory w znacznikach
//   <span> są w szablonie widżetów jako {{#nazwa}}: podmienia je
//   plude-lock.sh z linii `$nazwaHex` tego pliku.
// - wlogout (GTK3 CSS): @define-color w plude-colors.css (@import
//   w style.css) i tarcza wheel-plude.svg przemalowana z wheel.svg.
//   Same pełne kolory: w GTK półprzezroczyste prześwitują (DESIGN.md).
// ---------------------------------------------------------------
Scope {
    id: root

    readonly property string hyprDir: Quickshell.env("HOME") + "/.config/hypr"
    readonly property string wlogoutDir: Quickshell.env("HOME") + "/.config/wlogout"
    // Kąt gradientu ramek, jak w hyprland.lua.
    property int borderAngle: 22

    // c: tokeny jak w palette.json (#rrggbb).
    function write(c) {
        const h = s => s.replace("#", "");
        const header = "Wygenerowane przez PluDE (Common/PaletteExport.qml) z palety tapety. Nie edytuj.";

        // ---- Hyprland ----
        const lua = 'hl.config({ general = { col = { active_border = { colors = { "rgb(' + h(c.accent)
            + ')", "rgb(' + h(c.accent2) + ')" }, angle = ' + borderAngle + ' } } } })';
        hyprLua.setText("-- " + header + "\n" + lua + "\n");
        Quickshell.execDetached(["hyprctl", "eval", lua]);

        // ---- hyprlock ----
        const lockVars = {
            surfaceRaised: c.surfaceRaised, text: c.text, textDim: c.textDim,
            textFaint: c.textFaint, accent: c.accent, accent2: c.accent2
        };
        let lock = "# " + header + "\n";
        for (const k in lockVars) lock += "$" + k + " = rgb(" + h(lockVars[k]) + ")\n";
        lock += "$windowBorder = rgb(" + h(c.accent) + ") rgb(" + h(c.accent2) + ") " + borderAngle + "deg\n";
        lock += "# Dla plude-lock.sh: {{#nazwa}} w szablonie widżetów → ##rrggbb.\n";
        for (const k in lockVars) lock += "$" + k + "Hex = " + h(lockVars[k]) + "\n";
        lockColors.setText(lock);

        // ---- wlogout ----
        const css = {
            surface: c.surface,
            surfaceRaised: c.surfaceRaised,
            // Obrysy: tekst na surfaceRaised (jak Theme.border, tylko pełny).
            border: mix(c.surfaceRaised, c.text, 0.1),
            borderFocus: mix(c.surfaceRaised, c.text, 0.25),
            text: c.text,
            textDim: c.textDim,
            textFaint: c.textFaint,
            accent: c.accent,
            accentSoft: mix(c.surfaceRaised, c.accent, 0.2),
            accentSoftStrong: mix(c.surfaceRaised, c.accent, 0.34),
            warning: c.warning,
            warningSoft: mix(c.surfaceRaised, c.warning, 0.2),
            warningSoftStrong: mix(c.surfaceRaised, c.warning, 0.34),
            danger: c.danger,
            dangerSoft: mix(c.surfaceRaised, c.danger, 0.22),
            dangerSoftStrong: mix(c.surfaceRaised, c.danger, 0.36)
        };
        let out = "/* " + header + " */\n";
        for (const k in css) out += "@define-color " + k + " " + css[k] + ";\n";
        wlogoutCss.setText(out);

        wheel.colors = c;
        wheel.reload();
    }

    // Pełny kolor a + (b − a) × t z dwóch #rrggbb.
    function mix(a, b, t) {
        const ca = Qt.color(a), cb = Qt.color(b);
        const ch = (x, y) => ("0" + Math.round((x + (y - x) * t) * 255).toString(16)).slice(-2);
        return "#" + ch(ca.r, cb.r) + ch(ca.g, cb.g) + ch(ca.b, cb.b);
    }

    // Tylko zapis: bez preload FileView nie czyta pliku przy starcie
    // (brak pliku dawał „Read … failed” w logu).
    FileView { id: hyprLua; path: root.hyprDir + "/plude-colors.lua"; preload: false }
    FileView { id: lockColors; path: root.hyprDir + "/plude-lock-colors.conf"; preload: false }
    FileView { id: wlogoutCss; path: root.wlogoutDir + "/plude-colors.css"; preload: false }
    FileView { id: wheelOut; path: root.wlogoutDir + "/wheel-plude.svg"; preload: false }

    // Tarcza wlogouta: wheel.svg to szablon w stałych kolorach Theme,
    // podmieniamy je na paletę.
    FileView {
        id: wheel
        property var colors: null
        path: root.wlogoutDir + "/wheel.svg"
        blockLoading: false
        printErrors: false   // bez wlogouta nie ma czego malować
        onLoaded: {
            if (!colors) return;
            const map = {
                "#0a0a0c": colors.surface,
                "#17171a": colors.surfaceRaised,
                "#6a6a72": colors.textFaint,
                "#f2f2f2": colors.text,
                "#ffffff": colors.text
            };
            let svg = text();
            for (const k in map) svg = svg.split('"' + k + '"').join('"' + map[k] + '"');
            wheelOut.setText(svg);
        }
    }
}
