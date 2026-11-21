pragma Singleton

import QtQuick
import Quickshell

// ---------------------------------------------------------------
// Wspólny wygląd całego PluDE.
//
// Kolory idą z tapety (Wallpaper: skwd-wall + matugen). Bez palety zostają
// stałe wartości poniżej (`base*`), dawny niebieski przepisany z wyspy.
// Zmiana tapety nie przeskakuje: każdy kolor przechodzi do nowego
// w `paletteMs` (Behavior na właściwościach singletona działa, sprawdzone
// sondą), więc dock, pasek i otwarte panele zmieniają się naraz.
//
// Wyspa (osobny proces i repo) na razie zostaje przy stałych kolorach.
// ---------------------------------------------------------------
Singleton {
    id: root

    // Czas przejścia do kolorów nowej tapety.
    property int paletteMs: 900

    // ---- stałe kolory bez palety ----
    readonly property color baseSurface: "#0a0a0c"
    readonly property color baseSurfaceRaised: "#17171a"
    readonly property color baseSurfacePressed: "#2a2a2c"
    readonly property color baseText: "#f2f2f2"
    readonly property color baseTextDim: "#9a9aa2"
    readonly property color baseTextFaint: "#6a6a72"
    readonly property color baseAccent: "#5b8cff"
    readonly property color baseAccentBright: "#8fb0ff"
    readonly property color baseAccentDeep: "#1d3a7a"
    readonly property color baseAccentInk: "#0a1430"
    // Drugi odcień jak gradient ramek okien (fiolet → niebieski).
    readonly property color baseAccent2: "#a46bff"
    readonly property color baseAccent2Bright: "#c9a6ff"

    // ---------------------------------------------------------------
    // Tło i obrys
    // ---------------------------------------------------------------

    property color surface: Wallpaper.color("surface", baseSurface)
    property color surfaceRaised: Wallpaper.color("surfaceRaised", baseSurfaceRaised)
    // Wciśnięcie na surfaceRaised (pełny kolor, nie alfa).
    property color surfacePressed: Wallpaper.color("surfacePressed", baseSurfacePressed)
    // Obrysy z tekstu (zabarwionego paletą), więc też mają odcień tapety.
    readonly property color border: alpha(text, 0.08)
    readonly property color borderStrong: alpha(text, 0.16)
    readonly property color hover: alpha(text, 0.08)
    readonly property color hoverStrong: alpha(text, 0.16)

    // ---------------------------------------------------------------
    // Tekst
    // ---------------------------------------------------------------

    property color text: Wallpaper.color("text", baseText)
    property color textDim: Wallpaper.color("textDim", baseTextDim)
    property color textFaint: Wallpaper.color("textFaint", baseTextFaint)

    // ---------------------------------------------------------------
    // Akcenty
    // ---------------------------------------------------------------

    property color accent: Wallpaper.color("accent", baseAccent)
    // Jaśniejszy: tekst w akcencie, środek poświaty.
    property color accentBright: Wallpaper.color("accentBright", baseAccentBright)
    // Ciemny: wypełnienie zaznaczenia zamiast półprzezroczystego akcentu.
    property color accentDeep: Wallpaper.color("accentDeep", baseAccentDeep)
    // Tekst i ikony na pełnym akcencie.
    property color accentInk: Wallpaper.color("accentInk", baseAccentInk)
    // Drugi odcień (akcent obrócony o ~36°): gradienty, rzeczy „obok” akcentu.
    property color accent2: Wallpaper.color("accent2", baseAccent2)
    property color accent2Bright: Wallpaper.color("accent2Bright", baseAccent2Bright)

    // Odcień akcentu na przycisku (najechanie / wciśnięcie), pełny kolor.
    readonly property color accentSoft: mix(surfaceRaised, accent, 0.2)
    readonly property color accentSoftStrong: mix(surfaceRaised, accent, 0.34)

    Behavior on surface { ColorAnimation { duration: root.paletteMs } }
    Behavior on surfaceRaised { ColorAnimation { duration: root.paletteMs } }
    Behavior on surfacePressed { ColorAnimation { duration: root.paletteMs } }
    Behavior on text { ColorAnimation { duration: root.paletteMs } }
    Behavior on textDim { ColorAnimation { duration: root.paletteMs } }
    Behavior on textFaint { ColorAnimation { duration: root.paletteMs } }
    Behavior on accent { ColorAnimation { duration: root.paletteMs } }
    Behavior on accentBright { ColorAnimation { duration: root.paletteMs } }
    Behavior on accentDeep { ColorAnimation { duration: root.paletteMs } }
    Behavior on accentInk { ColorAnimation { duration: root.paletteMs } }
    Behavior on accent2 { ColorAnimation { duration: root.paletteMs } }
    Behavior on accent2Bright { ColorAnimation { duration: root.paletteMs } }

    // ---- kolory znaczące: stałe, niezależne od tapety ----
    readonly property color danger: "#e5484d"
    readonly property color success: "#38d47a"
    readonly property color warning: "#f0b232"
    readonly property color discord: "#5865f2"

    // ---------------------------------------------------------------
    // Pomocnicze
    // ---------------------------------------------------------------

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    // Pełny kolor: a + (b − a) × t (wzór z DESIGN.md).
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }
    // Tekst / ikona na pełnym kolorze: ciemny odcień tego koloru na jasnym
    // (akcent z palety ma ton 70), biały na ciemnym (danger, discord).
    function inkOn(c) {
        const lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        return lum > 0.5 ? mix(c, "#000000", 0.82) : "#ffffff";
    }
    // #rrggbb bez alfy (slurp, hyprctl, pliki konfiguracyjne).
    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2);
        return h(c.r) + h(c.g) + h(c.b);
    }

    // ---------------------------------------------------------------
    // Ruch
    // ---------------------------------------------------------------

    // Sprężyna wyspy: 520 ms OutBack z overshoot 0.9 (~3% ponad cel).
    readonly property int springMs: 520
    readonly property real springOvershoot: 0.9
    readonly property int fadeMs: 180
    readonly property int quickMs: 140
}
