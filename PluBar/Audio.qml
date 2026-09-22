pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// ---------------------------------------------------------------
// Głośność i mikrofon. Przepisane z AudioService wyspy (osobny proces,
// nie da się go zaimportować) i tak samo się zachowuje:
//
// - `audio` węzła istnieje tylko po związaniu PwObjectTrackerem,
// - skala 0–1 liniowo, ta sama co w wpctl,
// - mikrofon „wyłączony” = WSZYSTKIE źródła wyciszone, bo aplikacja może
//   słuchać innego wejścia niż domyślne.
//
// Zmiana głośności stąd to dla wyspy zmiana „z zewnątrz”: pokaże swój
// pasek w pigułce, tak jak po klawiszu multimedialnym.
// ---------------------------------------------------------------
Singleton {
    id: root

    property real step: 0.03   // jak volumeStep w wyspie

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.ready && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready && sink.audio.muted

    readonly property alias sinks: priv.sinks

    function sinkLabel(node) {
        if (!node) return "Brak wyjścia";
        return node.description || node.nickname || node.name || "?";
    }

    // Po nazwie węzła, jak w wyspie: bez bindowania PipeWire nie mówi, czym jest urządzenie.
    function sinkIcon(node) {
        if (!node) return "speaker";
        const n = ((node.name || "") + " " + (node.description || "")).toLowerCase();
        if (n.indexOf("hdmi") >= 0 || n.indexOf("displayport") >= 0) return "computer";
        if (n.indexOf("bluez") >= 0 || n.indexOf("headset") >= 0 || n.indexOf("headphone") >= 0) return "headset";
        return "speaker";
    }

    function setVolume(v) {
        if (!ready) return;
        if (muted && v > volume) sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, v));
    }

    function stepBy(delta) {
        setVolume(Math.round((volume + delta) * 100) / 100);
    }

    function toggleMute() {
        if (ready) sink.audio.muted = !sink.audio.muted;
    }

    function selectSink(node) {
        if (node) Pipewire.preferredDefaultAudioSink = node;
    }

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    // ---- mikrofon ----

    readonly property bool micReady: priv.boundSources.length > 0
    readonly property bool micOn: {
        const s = priv.boundSources;
        for (let i = 0; i < s.length; i++)
            if (!s[i].audio.muted) return true;
        return false;
    }

    function setMicOn(on) {
        const s = priv.boundSources;
        for (let i = 0; i < s.length; i++) s[i].audio.muted = !on;
    }

    PwObjectTracker { objects: priv.sources }

    QtObject {
        id: priv
        property var sinks: []
        property var sources: []
        readonly property var boundSources: sources.filter(n => n.ready && n.audio !== null)
    }

    function rebuild() {
        const v = Pipewire.nodes.values;
        const outSinks = [], outSources = [];
        for (let i = 0; i < v.length; i++) {
            const n = v[i];
            if (n.isStream) continue;
            if (n.isSink && n.type === PwNodeType.AudioSink) outSinks.push(n);
            else if (n.type === PwNodeType.AudioSource) outSources.push(n);
        }
        priv.sinks = outSinks;
        priv.sources = outSources;
    }

    Connections {
        target: Pipewire.nodes
        function onObjectInsertedPost() { root.rebuild(); }
        function onObjectRemovedPost() { root.rebuild(); }
    }

    Component.onCompleted: rebuild()
}
