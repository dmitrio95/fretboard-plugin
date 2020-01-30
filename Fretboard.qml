import QtQuick 2.6
import QtQuick.Controls 2.1
import QtQuick.Window 2.2
import MuseScore 3.0

MuseScore {
    id: fretplugin
    menuPath: "Plugins.Fretboard"
    version:  "0.2.0"
    description: "Simple guitar fretboard to visualise and edit tablature scores"
    requiresScore: false

    pluginType: "dock"
    dockArea: "bottom"

    implicitWidth: fretView.implicitWidth
    implicitHeight: fretView.implicitHeight

    QtObject {
        id: compatibility

        readonly property bool useApi334: mscoreVersion > 30303 // Cursor.addNote(pitch, addToChord), Cursor.prev()
    }

    readonly property bool darkMode: Window.window ? Window.window.color.hsvValue < 0.5 : false

    QtObject {
        id: style

        readonly property color textColor: fretplugin.darkMode ? "#EFF0F1" : "#333333"
        readonly property color backgroundColor: fretplugin.darkMode ? "#2C2C2C" : "#e3e3e3"
    }

    property var score: null
    property var cursor: null

    property var tuning: [64, 59, 55, 50, 45, 40, 0, 0, 0, 0] // default is 6-string classical guitar tuning

    function getPitch(string, fret) {
        return tuning[string] + fret;
    }

    readonly property var tpcNoteNames: [
        "F♭♭", "C♭♭", "G♭♭", "D♭♭", "A♭♭", "E♭♭", "B♭♭",
        "F♭", "C♭", "G♭", "D♭", "A♭", "E♭", "B♭",
        "F", "C", "G", "D", "A", "E", "B",
        "F♯", "C♯", "G♯", "D♯", "A♯", "E♯", "B♯",
        "F♯♯", "C♯♯", "G♯♯", "D♯♯", "A♯♯", "E♯♯", "B♯♯"
    ]
    function getNoteName(tpc) {
        return qsTranslate("InspectorAmbitus", tpcNoteNames[tpc + 1]);
    }

    function guessNoteName(string, fret) {
        var pitch = getPitch(string, fret);
        var key = cursor.keySignature;
        // copied from pitch2tpc FIXME
        var tpc = (pitch * 7 + 26 - (11 + key)) % 12 + (11 + key);
        return getNoteName(tpc);
    }

    function findSegment(e) {
        while (e && e.type != Element.SEGMENT)
            e = e.parent;
        return e;
    }

    function findSelectedChord() {
        if (!score)
            return null;

        var selectedElements = score.selection.elements;
        for (var i = 0; i < selectedElements.length; ++i) {
            var e = selectedElements[i];
            if (e.type == Element.NOTE) {
                var chord = e.parent;

                // HACK
                // removeElement(chord) may leave the chord selected,
                // so ensure this chord is really bound to a segment
                // or another chord as a grace note.
                var seg = findSegment(chord);
                var realChord = seg.elementAt(chord.track);

                if (!realChord || realChord.type != Element.CHORD)
                    return null;

                if (chord.is(realChord))
                    return chord;

                var grace = realChord.graceNotes;
                for (var i = 0; i < grace.length; ++i) {
                    if (grace[i].is(chord))
                        return chord;
                }

                return null;
            }
        }
    }

    function updateSelectedChord() {
        var chord = findSelectedChord();

        var frets = [];
        var noteInfo = [];
        for (var i = 0; i < tuning.length; ++i) {
            frets.push(-1);
            noteInfo.push("");
        }

        if (!chord) {
            fretView.selectedIndices = frets;
            fretView.selectedNotes = noteInfo;
            return;
        }

        var notes = chord.notes;
        for (var i = 0; i < notes.length; ++i) {
            var n = notes[i];
            if (n.string > -1 && n.fret > -1) {
                frets[n.string] = n.fret;
                noteInfo[n.string] = getNoteName(n.tpc);
                }
        }

        fretView.selectedIndices = frets;
        fretView.selectedNotes = noteInfo;
    }

    function updateCurrentScore() {
        if (curScore && !curScore.is(score)) {
            score = curScore;
            // Obtaining a cursor while in note input mode can lead to crashes, prevent this
            cmd("escape");
            cursor = score.newCursor();
        } else if (score && !curScore) {
            score = null;
            cursor = null;
        }
    }

    onScoreStateChanged: {
        updateCurrentScore();

        if (state.selectionChanged)
            updateSelectedChord();
    }

    onRun: {
        updateCurrentScore();
        updateSelectedChord();
    }

    function determineTuning(chord) {
        if (!chord)
            return;

        for (var i = 0; i < tuning.length; ++i)
            tuning[i] = 0;

        for (var i = 0; i < chord.notes.length; ++i) {
            var existingNote = chord.notes[i];
            tuning[existingNote.string] = existingNote.pitch - existingNote.fret;
        }

        var string = 0;
        var step = 12;

        for (var pitch = 127; pitch > 0; pitch -= step) {
            var testNote = newElement(Element.NOTE);
            testNote.string = string;
            testNote.pitch = pitch;

            curScore.startCmd();
            chord.add(testNote);
            curScore.endCmd();

            if (testNote.string > -1 && testNote.fret > -1) {
                const testNoteString = testNote.string;
                if (testNote.fret > 0) {
                    tuning[testNoteString] = pitch - testNote.fret;
                    string = testNoteString + 1;
                    // switch to a smaller step if haven't done it yet
                    step = 4;
                } else if (!tuning[testNoteString])
                    tuning[testNoteString] = pitch - testNote.fret;
            }

            cmd("undo");
        }

        // TODO: make it toggleable? Or make it done on each selection change (then record tunings for tracks?)
        var nstrings = 0;
        for (var i = 0; i < tuning.length; ++i) {
            if (tuning[i])
                nstrings = i + 1;
        }
        stringsComboBox.currentIndex = nstrings;

        console.log("guessed tuning:", tuning);
    }

    function addNoteWithCursor(string, fret, addToChord) {
        var oldNote = curScore.selection.elements[0];
        if (oldNote && oldNote.type != Element.NOTE)
            oldNote = null;

        if (compatibility.useApi334)
            cursor.addNote(fretplugin.getPitch(string, fret), addToChord);
        else
            cursor.addNote(fretplugin.getPitch(string, fret));

        var note = curScore.selection.elements[0]; // TODO: is there any better way to get the last added note?
        if (note && note.type != Element.NOTE)
            note = null;

        if (!note || note.is(oldNote)) {
            // no note has been added
            if (addToChord) {
                // fall back to adding a new note (maybe we are in a different voice?)
                return addNoteWithCursor(string, fret, false);
            }
            return null;
        }

        note.string = string;
        note.fret = fret;
        note.pitch = fretplugin.getPitch(string, fret);

        if (oldNote && oldNote.voice != note.voice) {
            // It is important to have a cursor on a correct string when
            // switching voices to have a correct chord selected. Try to
            // rewind tablature cursor to the correct string.
            //
            // TODO: rewind cursor in upside-down tablatures differently?
            // (we don't know about them in plugins currently)
            for (var i = 0; i < fretView.strings; ++i)
                cmd("string-above");
            for (var i = 0; i < note.string; ++i)
                cmd("string-below");
        }

        if (!cursor.segment.is(findSegment(note))) {
            if (compatibility.useApi334) {
                cursor.track = note.track;
                cursor.prev();
            }
        }

        return note;
    }

    function doAddNote(string, fret) {
        score.startCmd();

        var chord = findSelectedChord();
        var note = null;

        if (chord) {
            var chordNotes = chord.notes;
            for (var i = 0; i < chordNotes.length; ++i) {
                var chordNote = chordNotes[i];
                if (chordNote.string == string) {
                    note = chordNote;
                    break;
                }
            }

            if (note && note.string == string && note.fret == fret) {
                removeElement(note);
                // TODO: removing last note leaves the removed chord selected...
                // see HACK in findSelectedChord() to work around this
            } else {
                // To avoid computing TPC manually remove the old note
                // and insert the new one: TPC will be computed for it
                // automatically
                // TODO: or still compute TPC to preserve other properties?...
                var oldNote = note;

                if (compatibility.useApi334) {
                    note = addNoteWithCursor(string, fret, /* addToChord */ true);
                } else {
                    if (oldNote)
                        note = note.clone();
                    else
                        note = newElement(Element.NOTE);

                    note.string = string;
                    note.fret = fret;
                    note.pitch = fretplugin.getPitch(string, fret);

                    chord.add(note);
                }

                // removing the old note after adding the new one
                // since otherwise we may happen to delete the last
                // note of a chord which is forbidden.
                if (oldNote)
                    chord.remove(oldNote);
            }
        } else {
            note = addNoteWithCursor(string, fret, /* addToChord */ false);
        }

        score.endCmd();

        return note;
    }

    function addNote(string, fret) {
        if (!score.is(curScore))
            return;

        var note = doAddNote(string, fret);

        if (note && (note.string != string || note.fret != fret)) {
            console.log("couldn't add a note, try changing tuning...")
            var chord = note.parent;
            determineTuning(chord);
            cmd("undo");

            // try with the adjusted tuning
            note = doAddNote(string, fret);
            if (note && (note.string != string || note.fret != fret)) {
                console.log("still couldn't add a note, revert")
                cmd("undo");
            }
        }

        // our changes may have not triggered selection change
        updateSelectedChord();
    }

    Component {
        id: dotComponent
        Rectangle {
            height: 16
            width: 16
            radius: 16

            color: "black"
        }
    }

    Component {
        id: markerComponent

        Rectangle {
            id: marker
            property string text: ""

            height: 18
            width: 18
            radius: 18

            color: "red"

            Text {
                anchors.centerIn: parent
                font.pixelSize: 14
                fontSizeMode: Text.Fit
                text: marker.text
            }
        }
    }

    Column {
        id: fretSettings

        width: Math.max(stringsComboBox.implicitWidth, fretsComboBox.implicitWidth)

        Row {
            anchors.horizontalCenter: parent.horizontalCenter

            ToolButton {
                text: "<"
                onClicked: cmd("prev-chord")

                ToolTip.visible: hovered
                ToolTip.delay: Qt.styleHints.mousePressAndHoldInterval
                ToolTip.text: qsTranslate("action", "Previous Chord")

                Component.onCompleted: contentItem.color = Qt.binding(function() { return style.textColor; })
            }
            ToolButton {
                text: ">"
                onClicked: cmd("next-chord")

                ToolTip.visible: hovered
                ToolTip.delay: Qt.styleHints.mousePressAndHoldInterval
                ToolTip.text: qsTranslate("action", "Next Chord")

                Component.onCompleted: contentItem.color = Qt.binding(function() { return style.textColor; })
            }
        }

        ToolSeparator {
            width: parent.width
            orientation: Qt.Horizontal
        }

        ComboBox {
            id: stringsComboBox
            width: parent.width

            currentIndex: 6
            displayText: qsTranslate("InspectorFretDiagram", "Strings:") + " " + currentText
            model: 11

            contentItem: Text {
                leftPadding: !stringsComboBox.mirrored ? 12 : 1
                rightPadding: stringsComboBox.mirrored ? 12 : 1
                text: parent.displayText
                color: style.textColor
                verticalAlignment: Text.AlignVCenter
            }

            Component.onCompleted: background.color = Qt.binding(function() { return style.backgroundColor; })
        }

        ComboBox {
            id: fretsComboBox
            width: parent.width

            currentIndex: 19
            displayText: qsTranslate("InspectorFretDiagram", "Frets:") + " " + currentText
            model: 51

            contentItem: Text {
                leftPadding: !fretsComboBox.mirrored ? 12 : 1
                rightPadding: fretsComboBox.mirrored ? 12 : 1
                text: parent.displayText
                color: style.textColor
                verticalAlignment: Text.AlignVCenter
            }

            Component.onCompleted: background.color = Qt.binding(function() { return style.backgroundColor; })
        }
    }

    Component {
        id: fretNormalComponent

        Rectangle {
            property bool hasTopHalfDot: false
            property bool hasBottomHalfDot: false
            color: "brown"

            clip: true

            Rectangle {
                width: 1
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                color: "white"
            }

            Rectangle {
                height: 2
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                color: "black"
            }

            Loader {
                sourceComponent: parent.hasTopHalfDot ? dotComponent : null
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.top }
            }
            Loader {
                sourceComponent: parent.hasBottomHalfDot ? dotComponent : null
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.bottom }
            }
        }
    }

    Component {
        id: fretZeroComponent

        Item {
            property bool hasTopHalfDot: false
            property bool hasBottomHalfDot: false

            Rectangle {
                id: fretZero
                width: parent.width / 2
                anchors {
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }
                color: "darkgrey"
            }

            Rectangle {
                height: 2
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                color: "black"
            }
        }
    }

    Grid {
        id: fretView

        anchors {
            left: fretSettings.right
            leftMargin: 8
        }

        property var selectedIndices: []
        property var selectedNotes: []

        property int frets: +fretsComboBox.currentText + 1
        property int strings: +stringsComboBox.currentText

        columns: frets
        rows: strings

        property var dots: [3, 5, 7, 9, 15, 17, 19, 21]
        property var doubleDots: [12, 24]

        function hasDot(string, fret) {
            if (string == 0)
                return false;

            var mid = Math.floor(strings / 2);

            if (string == mid - 1 || string == mid + 1)
                return doubleDots.indexOf(fret) != -1;
            if (string == mid)
                return dots.indexOf(fret) != -1;
            return false;
        }

        Repeater {
            model: fretView.frets * fretView.strings

            delegate: ItemDelegate {
                id: fretRect
                implicitWidth: 70 * Math.pow(0.96, fret)
                implicitHeight: 25

                property bool marked: fretView.selectedIndices[str] == fret

                property int str: Math.floor(model.index / fretView.frets)
                property int fret: model.index % fretView.frets

                onClicked: fretplugin.addNote(str, fret)

                background: Loader {
                    id: loader
                    sourceComponent: fret === 0 ? fretZeroComponent : fretNormalComponent
                    Binding { target: loader.item; property: "hasTopHalfDot"; value: fretView.hasDot(fretRect.str, fretRect.fret) }
                    Binding { target: loader.item; property: "hasBottomHalfDot"; value: fretRect.str + 1 < fretView.strings && fretView.hasDot(fretRect.str + 1, fretRect.fret) }
                }

                Loader {
                    id: markerLoader
                    sourceComponent: markerComponent
                    anchors.centerIn: parent
                    visible: fretRect.marked || fretRect.hovered
                    opacity: fretRect.marked ? 1.0 : 0.67
                    onVisibleChanged: {
                        if (visible && !fretRect.marked)
                            markerLoader.item.text = fretplugin.guessNoteName(fretRect.str, fretRect.fret);
                    }
                }

                onMarkedChanged: {
                    if (marked)
                        markerLoader.item.text = Qt.binding(function() { return fretView.selectedNotes[str]; });
                    else
                        markerLoader.item.text = fretplugin.guessNoteName(fretRect.str, fretRect.fret);
                }
            }
        }
    }
}
