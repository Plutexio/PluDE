//@ pragma UseQApplication
// Bez tego Quickshell widzi tylko hicolor (zmierzone: application-x-executable,
// network-wired, applications-games → brak) i część aplikacji nie ma ikon.
// breeze-dark, bo dock i launcher są ciemne.
//@ pragma IconTheme breeze-dark

import QtQuick
import Quickshell

// Punkt wejścia PluDE (dock + launcher). Uruchom:  qs -p ~/PluDE
//
// Wyspa (~/PluDynamicIsland) chodzi jako OSOBNY proces — Quickshell
// przeładowuje cały proces przy każdej zmianie pliku, a restart wyspy to
// nowe okno zgody Discorda i restart jej mostków. Rozmowa z nią: Common/IslandLink.
//
// Całość działa tylko na Hyprlandzie. Na innym kompozytorze (KDE) nie
// ładujemy niczego: Main.qml importuje Quickshell.Hyprland, a sam import
// na KDE daje ostrzeżenia o braku protokołów — stąd Loader po nazwie pliku.
ShellRoot {
    id: root

    readonly property bool onHyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== undefined
        && Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== null

    Loader {
        active: root.onHyprland
        source: "Main.qml"
    }

    Component.onCompleted: {
        if (!onHyprland) console.info("PluDE: to nie Hyprland — dock i launcher wyłączone.");
    }
}
