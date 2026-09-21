pragma Singleton

import QtQuick
import Quickshell

// ---------------------------------------------------------------
// Wspólny wygląd docka i launchera. Wartości przepisane z wyspy
// (~/PluDynamicIsland), żeby wszystkie trzy wyglądały jak jeden system —
// wyspa to osobny proces i osobne repo, więc nie importujemy jej plików,
// tylko trzymamy te same liczby. Zmieniasz kolor tutaj → zmień go też tam.
// ---------------------------------------------------------------
Singleton {
    // ---- tło i obrys (jak ClippingRectangle wyspy) ----
    readonly property color surface: "#0a0a0c"
    readonly property color surfaceRaised: "#17171a"
    readonly property color border: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hover: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hoverStrong: Qt.rgba(1, 1, 1, 0.16)

    // ---- tekst ----
    readonly property color text: "#f2f2f2"
    readonly property color textDim: "#9a9aa2"
    readonly property color textFaint: "#6a6a72"

    // ---- akcenty ----
    readonly property color accent: "#5b8cff"
    readonly property color danger: "#e5484d"
    readonly property color success: "#38d47a"
    readonly property color warning: "#f0b232"
    readonly property color discord: "#5865f2"

    // ---- ruch ----
    // Sprężyna wyspy: 520 ms OutBack z overshoot 0.9 (~3% ponad cel).
    readonly property int springMs: 520
    readonly property real springOvershoot: 0.9
    readonly property int fadeMs: 180
    readonly property int quickMs: 140
}
