import QtQuick
import QtQuick.Shapes

// Ikona wektorowa w siatce 24 × 24, jak IslandIcon w wyspie (część ścieżek
// przepisana stamtąd). Wektor, a nie ikona z motywu: stan (siła sygnału,
// wyciszenie) ma wyglądać tak samo niezależnie od motywu ikon.
//
// ghost: druga ścieżka pod spodem w przygaszonym kolorze. Tak rysujemy
// poziom (siła Wi-Fi): pełny kształt blado, wypełniona część na wierzchu.
Item {
    id: root

    property string kind: "wifi"
    property string ghost: ""
    property real size: 16
    property color color: Theme.text
    property color ghostColor: Theme.textFaint

    // Material Icons (Apache 2.0) albo własne. Wypełnienie WindingFill:
    // dziura to wewnętrzny kontur w PRZECIWNYM kierunku (pułapka z wyspy).
    readonly property var paths: ({
        // Wi-Fi rozłożone na trzy łuki, żeby rysować siłę sygnału.
        "wifi":  "M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.93 2.93 7.08 2.93 1 9z M5 13l2 2c2.76-2.76 7.24-2.76 10 0l2-2C15.14 9.14 8.87 9.14 5 13z M9 17l3 3 3-3c-1.65-1.66-4.34-1.66-6 0z",
        "wifi2": "M5 13l2 2c2.76-2.76 7.24-2.76 10 0l2-2C15.14 9.14 8.87 9.14 5 13z M9 17l3 3 3-3c-1.65-1.66-4.34-1.66-6 0z",
        "wifi1": "M9 17l3 3 3-3c-1.65-1.66-4.34-1.66-6 0z",
        "wifiOff": "M22.99 9C19.15 5.16 13.8 3.76 8.84 4.78l2.52 2.52c3.47-.17 6.99 1.05 9.63 3.7l2-2zm-4 4c-1.29-1.29-2.84-2.13-4.49-2.56l3.53 3.53.96-.97zM2 3.05L5.07 6.1C3.6 6.82 2.22 7.78 1 9l1.99 2c1.24-1.24 2.67-2.16 4.2-2.77l2.24 2.24C7.81 10.89 6.27 11.73 5 13v.01L6.99 15c1.36-1.36 3.14-2.04 4.92-2.06L18.98 20l1.27-1.26L3.29 1.79 2 3.05zM9 17l3 3 3-3c-1.65-1.66-4.34-1.66-6 0z",
        // Monitor z wyciętym ekranem (kontur wewnętrzny w przeciwną stronę).
        "wired": "M4 4h16v11h-6v2h3v2H7v-2h3v-2H4z M6 6v7h12V6z",
        "bluetooth": "M17.71 7.71L12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29zM13 5.83l1.88 1.88L13 9.59V5.83zm1.88 10.46L13 18.17v-3.76l1.88 1.88z",
        "bluetoothConnected": "M7 12l-2-2-2 2 2 2 2-2zm10.71-4.29L12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29zM13 5.83l1.88 1.88L13 9.59V5.83zm1.88 10.46L13 18.17v-3.76l1.88 1.88zM19 10l-2 2 2 2 2-2-2-2z",
        "bluetoothOff": "M13 5.83l1.88 1.88-1.6 1.6 1.41 1.41 3.02-3.02L12 2h-1v5.03l2 2v-3.2zM5.41 4L4 5.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l4.29-4.29 2.3 2.29L20 18.59 5.41 4zM13 18.17v-3.76l1.88 1.88L13 18.17z",
        "volume": "M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z",
        "volumeLow": "M18.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM5 9v6h4l5 5V4L9 9H5z",
        "volumeMute": "M7 9v6h4l5 5V4l-5 5H7z",
        "volumeOff": "M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z",
        "mic": "M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3zm5.3-3c0 3-2.54 5.1-5.3 5.1S6.7 14 6.7 11H5c0 3.41 2.72 6.23 6 6.72V21h2v-3.28c3.28-.48 6-3.3 6-6.72h-1.7z",
        "micOff": "M19 11h-1.7c0 .74-.16 1.43-.43 2.05l1.23 1.23c.56-.98.9-2.09.9-3.28zm-4.02.17c0-.06.02-.11.02-.17V5c0-1.66-1.34-3-3-3S9 3.34 9 5v.18l5.98 5.99zM4.27 3L3 4.27l6.01 6.01V11c0 1.66 1.33 3 2.99 3 .22 0 .44-.03.65-.08l1.66 1.66c-.71.33-1.5.52-2.31.52-2.76 0-5.3-2.1-5.3-5.1H5c0 3.41 2.72 6.23 6 6.72V21h2v-3.28c.91-.13 1.77-.45 2.54-.9L19.73 21 21 19.73 4.27 3z",
        // Słońce: koło r=4 i 8 zaokrąglonych promieni co 45° (policzone skryptem).
        "brightness": "M12 8a4 4 0 1 1 0 8a4 4 0 1 1 0-8z M18.6 13 L21.6 13 A1 1 0 0 0 21.6 11 L18.6 11 A1 1 0 0 0 18.6 13 z M15.96 17.37 L18.08 19.5 A1 1 0 0 0 19.5 18.08 L17.37 15.96 A1 1 0 0 0 15.96 17.37 z M11 18.6 L11 21.6 A1 1 0 0 0 13 21.6 L13 18.6 A1 1 0 0 0 11 18.6 z M6.63 15.96 L4.5 18.08 A1 1 0 0 0 5.92 19.5 L8.04 17.37 A1 1 0 0 0 6.63 15.96 z M5.4 11 L2.4 11 A1 1 0 0 0 2.4 13 L5.4 13 A1 1 0 0 0 5.4 11 z M8.04 6.63 L5.92 4.5 A1 1 0 0 0 4.5 5.92 L6.63 8.04 A1 1 0 0 0 8.04 6.63 z M13 5.4 L13 2.4 A1 1 0 0 0 11 2.4 L11 5.4 A1 1 0 0 0 13 5.4 z M17.37 8.04 L19.5 5.92 A1 1 0 0 0 18.08 4.5 L15.96 6.63 A1 1 0 0 0 17.37 8.04 z",
        // Profile energii: liść, wskaźnik ze wskazówką w górę, wskaźnik „na maksa”.
        "powerSaver": "M6.05 8.05c-2.73 2.73-2.73 7.15-.02 9.88 1.47-3.4 4.09-6.24 7.37-7.93-2.78 2.34-4.72 5.61-5.39 9.32 2.6 1.23 5.8.78 7.95-1.37C19.43 14.47 20 4 20 4S9.53 4.57 6.05 8.05z",
        "balanced": "M20.38 8.57l-1.23 1.85a8 8 0 0 1-.22 7.58H5.07A8 8 0 0 1 15.58 6.85l1.85-1.23A10 10 0 0 0 3.35 19a2 2 0 0 0 1.72 1h13.85a2 2 0 0 0 1.74-1 10 10 0 0 0-.27-10.44z M12 7.5l1.4 6.1a1.45 1.45 0 1 1-2.8 0z",
        "performance": "M20.38 8.57l-1.23 1.85a8 8 0 0 1-.22 7.58H5.07A8 8 0 0 1 15.58 6.85l1.85-1.23A10 10 0 0 0 3.35 19a2 2 0 0 0 1.72 1h13.85a2 2 0 0 0 1.74-1 10 10 0 0 0-.27-10.44zm-9.79 6.84a2 2 0 0 0 2.83 0l5.66-8.49-8.49 5.66a2 2 0 0 0 0 2.83z",
        "power": "M13 3h-2v10h2V3zm4.83 2.17l-1.42 1.42C17.99 7.86 19 9.81 19 12c0 3.87-3.13 7-7 7s-7-3.13-7-7c0-2.19 1.01-4.14 2.58-5.42L6.17 5.17C4.23 6.82 3 9.26 3 12c0 4.97 4.03 9 9 9s9-4.03 9-9c0-2.74-1.23-5.18-3.17-6.83z",
        "bolt": "M11 21h-1l1-7H7.5c-.58 0-.57-.32-.38-.66.19-.34.05-.08.07-.12C8.48 10.94 10.42 7.54 13 3h1l-1 7h3.5c.49 0 .56.33.47.51l-.07.15C12.96 17.55 11 21 11 21z",
        "speaker": "M17 2H7c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-5 2c1.1 0 2 .9 2 2s-.9 2-2 2c-1.11 0-2-.9-2-2s.89-2 2-2zm0 16c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z",
        "headset": "M12 1c-4.97 0-9 4.03-9 9v7c0 1.66 1.34 3 3 3h3v-8H5v-2c0-3.87 3.13-7 7-7s7 3.13 7 7v2h-4v8h3c1.66 0 3-1.34 3-3v-7c0-4.97-4.03-9-9-9z",
        // Ustawienia ogólne (suwaki) i strzałka listy wyboru.
        "tune": "M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z",
        "expand": "M16.59 8.59L12 13.17 7.41 8.59 6 10l6 6 6-6z",
        "computer": "M20 18c1.1 0 1.99-.9 1.99-2L22 6c0-1.1-.9-2-2-2H4c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2H0v2h24v-2h-4zM4 6h16v10H4V6z",
        // Schowek i zrzuty ekranu.
        "paste": "M19 2h-4.18C14.4.84 13.3 0 12 0c-1.3 0-2.4.84-2.82 2H5c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-7 0c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm7 18H5V4h2v3h10V4h2v16z",
        "text": "M3 18h12v-2H3v2zM3 6v2h18V6H3zm0 7h18v-2H3v2z",
        "link": "M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z",
        "image": "M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z",
        "pin": "M16 9V4h1c.55 0 1-.45 1-1s-.45-1-1-1H7c-.55 0-1 .45-1 1s.45 1 1 1h1v5c0 1.66-1.34 3-3 3v2h5.97v7l1 1 1-1v-7H19v-2c-1.66 0-3-1.34-3-3z",
        "trash": "M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z",
        "edit": "M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z",
        "folder": "M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z",
        "warning": "M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"
    })

    implicitWidth: size
    implicitHeight: size

    Shape {
        visible: root.ghost !== ""
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: root.size / 24
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.ghostColor
            strokeWidth: 0
            strokeColor: "transparent"
            fillRule: ShapePath.WindingFill
            PathSvg { path: root.paths[root.ghost] ?? "" }
        }
    }

    Shape {
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: root.size / 24
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            strokeWidth: 0
            strokeColor: "transparent"
            fillRule: ShapePath.WindingFill
            PathSvg { path: root.paths[root.kind] ?? "" }
        }
    }
}
