import QtQuick 2.6
import QtQuick.Controls 2.1
import QtQuick.Window 2.2
import MuseScore 3.0

Item {
    id: fretplugin

    // Reference to the plugin, gives access to the main MuseScore plugin API.
    property var mscore: null

    implicitWidth: fretView.implicitWidth
    implicitHeight: fretView.implicitHeight

    QtObject {
        id: compatibility

        readonly property bool useApi334: mscore ? (mscore.mscoreVersion > 30303) : false // Cursor.addNote(pitch, addToChord), Cursor.prev()
        readonly property bool useApi350: mscore ? (mscore.mscoreVersion >= 30500) : false // instrument data, range selection
        readonly property bool useApi4: mscore ? (mscore.mscoreVersion >= 40000) : false
    }

    readonly property bool darkMode: Window.window ? Window.window.color.hsvValue < 0.5 : false

    QtObject {
        id: style

        readonly property color textColor: fretplugin.darkMode ? "#EFF0F1" : "#333333"
        readonly property color backgroundColor: fretplugin.darkMode ? "#2C2C2C" : "#e3e3e3"
    }

    property var score: null
    property var cursor: null
    property int cursorLastTick: -1

    property var instrument: null
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
        var name = tpcNoteNames[tpc + 1];
        if (compatibility.useApi4) {
            return qsTranslate("action", name[0]) + name.substr(1);
        } else {
            return qsTranslate("InspectorAmbitus", name);
        }
    }

    function guessNoteName(string, fret) {
        var pitch = getPitch(string, fret);
        var key = cursor.keySignature;
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

        // Prevent the previous chord being considered a current position when
        // moving to the next measure in the second (or greater) voice.
        if (!cursor.element)
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

        if (chord) {
            setDisplayedNotes(chord.notes);
        } else {
            setDisplayedNotes([]);
        }
    }

    function updateSelection() {
        if (score.selection.isRange) { // MuseScore 3.5+
            var selectedElements = score.selection.elements;
            var notes = [];

            for (var i = 0; i < selectedElements.length; ++i) {
                var e = selectedElements[i];
                if (e.type == Element.NOTE) {
                    notes.push(e);
                }
            }

            setDisplayedNotes(notes);
        } else {
            updateSelectedChord();
        }

        updateInstrumentData();
        cursorLastTick = cursor.tick;
    }

    function updateInstrumentData() {
        if (!compatibility.useApi350)
            return;

        var e = score.selection.elements[0];
        var seg = findSegment(e);

        if (!e || !seg)
            return;

        var newPart = e.staff.part;

        if (!newPart || !newPart.hasTabStaff)
            return;

        var newInstrument = newPart.instrumentAtTick(seg.tick);

        if (!newInstrument || newInstrument.is(fretplugin.instrument))
            return;

        fretplugin.instrument = newInstrument;
        var stringData = newInstrument.stringData;

        if (stringData.frets <= 0)
            return;

        var strings = stringData.strings;
        var newTuning = [];

        for (var i = 0; i < strings.length; ++i) {
            newTuning.push(strings[i].pitch);
        }

        // The plugin uses string data in reverse order.
        newTuning.reverse();

        if (e.type == Element.NOTE) {
            var transposition = getTransposition(newTuning, e);
            if (transposition) {
                applyTransposition(newTuning, transposition);
            }
        }

        if (newTuning.length > 0) {
            fretplugin.tuning = newTuning;
            stringsComboBox.currentIndex = newTuning.length;
            fretsComboBox.currentIndex = stringData.frets;
        }

        console.log("new tuning:", newTuning);
    }

    function getFretIndex(string, fret) {
        return tuning.length * fret + string;
    }

    function setDisplayedNotes(notes) {
        var noteInfo = {};

        for (var i = 0; i < notes.length; ++i) {
            var n = notes[i];
            if (n.string > -1 && n.fret > -1) {
                var idx = getFretIndex(n.string, n.fret);
                noteInfo[idx] = getNoteName(n.tpc);
            }
        }

        fretView.selectedNotes = noteInfo;
    }

    function updateCurrentScore() {
        if (mscore.curScore && !mscore.curScore.is(score)) {
            score = mscore.curScore;
            cursor = score.newCursor();
            if (typeof cursor.inputStateMode !== "undefined") {
                // Possible future versions API expansion
                cursor.inputStateMode = Cursor.INPUT_STATE_SYNC_WITH_SCORE;
            } else {
                // Obtaining a cursor while in note input mode can lead to crashes, prevent this
                mscore.cmd("escape");
                cursor = score.newCursor();
            }
        } else if (score && !mscore.curScore) {
            score = null;
            cursor = null;
        }
    }

    function updateState(selectionChanged) {
        updateCurrentScore();

        if (selectionChanged || cursor.tick != cursorLastTick)
            updateSelection();
    }

    function onRun() {
        updateCurrentScore();
        updateSelection();
    }

    function determineTuning(chord) {
        if (!chord)
            return;

        if (compatibility.useApi350) {
            // We use string data directly with this API, so it should be
            // sufficient just to figure out instrument transposition.
            var note = chord.notes[0];
            var step = 12;
            var transposition = getTransposition(tuning, note);

            if (transposition) {
                applyTransposition(tuning, transposition);
            } else {
                for (var pitch = 127; pitch > 0; pitch -= step) {
                    var testNote = mscore.newElement(Element.NOTE);
                    testNote.string = string;
                    testNote.pitch = pitch;

                    mscore.curScore.startCmd();
                    chord.add(testNote);
                    mscore.curScore.endCmd();

                    transposition = getTransposition(tuning, testNote);
                    mscore.cmd("undo");

                    if (transposition) {
                        applyTransposition(tuning, transposition);
                        break;
                    }
                }
            }

            console.log("guessed tuning (transposition):", tuning);
            return;
        }

        for (var i = 0; i < tuning.length; ++i)
            tuning[i] = 0;

        for (var i = 0; i < chord.notes.length; ++i) {
            var existingNote = chord.notes[i];
            tuning[existingNote.string] = existingNote.pitch - existingNote.fret;
        }

        var string = 0;
        var step = 12;

        for (var pitch = 127; pitch > 0; pitch -= step) {
            var testNote = mscore.newElement(Element.NOTE);
            testNote.string = string;
            testNote.pitch = pitch;

            mscore.curScore.startCmd();
            chord.add(testNote);
            mscore.curScore.endCmd();

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

            mscore.cmd("undo");
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

    function getTransposition(tuning, note) {
        // Out-of-range notes seem to have fret 0, so we cannot
        // rely on fret-0 notes to determine transposition.
        if (note.string > -1 && note.fret > 0)
            return note.pitch - note.fret - tuning[note.string];
        return 0;
    }

    function applyTransposition(tuning, transposition) {
        for (var i = 0; i < tuning.length; ++i) {
            if (tuning[i]) {
                tuning[i] += transposition;
            }
        }
    }

    function addNoteWithCursor(string, fret, addToChord) {
        var oldNote = mscore.curScore.selection.elements[0];
        if (oldNote && oldNote.type != Element.NOTE)
            oldNote = null;

        if (compatibility.useApi334)
            cursor.addNote(fretplugin.getPitch(string, fret), addToChord);
        else
            cursor.addNote(fretplugin.getPitch(string, fret));

        var note = mscore.curScore.selection.elements[0]; // TODO: is there any better way to get the last added note?
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

        if (typeof cursor.stringNumber !== "undefined") {
            // Possible future versions API expansion
            cursor.stringNumber = note.string;
        } else if (oldNote && oldNote.voice != note.voice) {
            // It is important to have a cursor on a correct string when
            // switching voices to have a correct chord selected. Try to
            // rewind tablature cursor to the correct string.
            for (var i = 0; i < fretView.strings; ++i)
                mscore.cmd("string-above");
            for (var i = 0; i < note.string; ++i)
                mscore.cmd("string-below");
        }

        if (compatibility.useApi334) {
            if (!cursor.segment.is(findSegment(note))) {
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
                mscore.removeElement(note);
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
                        note = mscore.newElement(Element.NOTE);

                    note.string = string;
                    note.fret = fret;
                    note.pitch = fretplugin.getPitch(string, fret);

                    chord.add(note);
                }

                // removing the old note after adding the new one
                // since otherwise we may happen to delete the last
                // note of a chord which is forbidden.
                if (oldNote) {
                    chord.remove(oldNote);
                }
            }
        } else {
            note = addNoteWithCursor(string, fret, /* addToChord */ false);
        }

        score.endCmd();

        if (compatibility.useApi4) {
            // Note playback hack.
            var moveAndPlayCmd = "";

            if (cursor.tick > 0) {
                cursor.prev();
                moveAndPlayCmd = "next-chord";
            } else {
                cursor.next();
                moveAndPlayCmd = "prev-chord";
            }

            var cursorElement = cursor.element;
            var selectedElement = score.selection.elements[0];

            if (cursorElement && selectedElement) {
                var cursorSegment = findSegment(cursor.element);
                var selectedSegment = findSegment(selectedElement);

                // Seems to be the case if changing a chord not in note input mode.
                if (!cursorSegment.is(selectedElement)) {
                    var newSelectionElement = (cursorElement.type == Element.CHORD)
                        ? cursorElement.notes[0]
                        : cursorElement;
                    score.selection.select(newSelectionElement);
                }
            }

            cursor.track = note.track;
            cmd(moveAndPlayCmd);
        }

        return note;
    }

    function addNote(string, fret) {
        if (!score.is(mscore.curScore))
            return;

        if (score.selection.isRange) // MuseScore 3.5+
            return;

        var note = doAddNote(string, fret);

        if (note && (note.string != string || note.fret != fret)) {
            console.log("couldn't add a note, try changing tuning...")
            var chord = note.parent;
            determineTuning(chord);
            mscore.cmd("undo");

            // try with the adjusted tuning
            note = doAddNote(string, fret);
            if (note && (note.string != string || note.fret != fret)) {
                console.log("still couldn't add a note, revert")
                mscore.cmd("undo");
            }
        }

        // our changes may have not triggered selection change
        updateSelection();
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
                onClicked: mscore.cmd("prev-chord")

                ToolTip.visible: hovered
                ToolTip.delay: Qt.styleHints.mousePressAndHoldInterval
                ToolTip.text: compatibility.useApi4
                    ? qsTranslate("action", "Previous chord / Shift text left")
                    : qsTranslate("action", "Previous Chord")

                contentItem: Text {
                    text: "<"
                    color: style.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            ToolButton {
                onClicked: mscore.cmd("next-chord")

                ToolTip.visible: hovered
                ToolTip.delay: Qt.styleHints.mousePressAndHoldInterval
                ToolTip.text: compatibility.useApi4
                    ? qsTranslate("action", "Next chord / Shift text right")
                    : qsTranslate("action", "Next Chord")

                contentItem: Text {
                    text: ">"
                    color: style.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
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
            readonly property string baseText: compatibility.useApi4
                ? qsTranslate("EditStaffBase", "Number of strings:")
                : qsTranslate("InspectorFretDiagram", "Strings:")
            displayText: baseText + " " + currentText
            model: 11

            contentItem: Text {
                leftPadding: !stringsComboBox.mirrored ? 12 : 1
                rightPadding: stringsComboBox.mirrored ? 12 : 1
                text: parent.displayText
                color: style.textColor
                verticalAlignment: Text.AlignVCenter
            }

            Component.onCompleted: {
                if (compatibility.useApi4) {
                    background.text = "";
                } else {
                    background.color = Qt.binding(function() { return style.backgroundColor; });
                }
            }
        }

        ComboBox {
            id: fretsComboBox
            width: parent.width

            currentIndex: 19
            readonly property string baseText: compatibility.useApi4
                ? qsTranslate("EditStringDataBase", "Number of frets:")
                : qsTranslate("InspectorFretDiagram", "Frets:")
            displayText: baseText + " " + currentText
            model: 51

            contentItem: Text {
                leftPadding: !fretsComboBox.mirrored ? 12 : 1
                rightPadding: fretsComboBox.mirrored ? 12 : 1
                text: parent.displayText
                color: style.textColor
                verticalAlignment: Text.AlignVCenter
            }

            Component.onCompleted: {
                if (compatibility.useApi4) {
                    background.text = "";
                } else {
                    background.color = Qt.binding(function() { return style.backgroundColor; });
                }
            }
        }

        Loader {
            id: leftHandedCheckBox
            width: parent.width
            property bool checked: item.checked

            source: compatibility.useApi4 ? "MU4CheckBox.qml" : undefined
            sourceComponent: compatibility.useApi4 ? undefined : mu3checkBoxComponent

            // Show full text in a tooltip if it doesn't fit into width.
            ToolTip.visible: (item.width < item.implicitWidth) && item.hovered
            ToolTip.delay: Qt.styleHints.mousePressAndHoldInterval
            ToolTip.text: item.text

            Component {
                id: mu3checkBoxComponent
                CheckBox {
                    Component.onCompleted: contentItem.color = Qt.binding(function() { return style.textColor; })
                }
            }

            onLoaded: {
                item.checked = false;
                item.text = qsTranslate("action", "Flip direction");
            }
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
                    left: fretView.leftHanded ? undefined : (parent ? parent.left : undefined)
                    right: fretView.leftHanded ? (parent ? parent.right : undefined) : undefined
                    top: parent ? parent.top : undefined
                    bottom: parent ? parent.bottom : undefined
                }
                color: "white"
            }

            Rectangle {
                height: 2
                anchors {
                    left: parent ? parent.left : undefined
                    right: parent ? parent.right : undefined
                    verticalCenter: parent ? parent.verticalCenter : undefined
                }
                color: "black"
            }

            Loader {
                sourceComponent: parent.hasTopHalfDot ? dotComponent : null
                anchors {
                    horizontalCenter: parent ? parent.horizontalCenter : undefined
                    verticalCenter: parent ? parent.top : undefined
                }
            }
            Loader {
                sourceComponent: parent.hasBottomHalfDot ? dotComponent : null
                anchors {
                    horizontalCenter: parent ? parent.horizontalCenter : undefined
                    verticalCenter: parent ? parent.bottom : undefined
                }
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
                    right: parent ? parent.right : undefined
                    top: parent ? parent.top : undefined
                    bottom: parent ? parent.bottom : undefined
                }
                color: "darkgrey"
            }

            Rectangle {
                height: 2
                anchors {
                    left: parent ? parent.left : undefined
                    right: parent ? parent.right : undefined
                    verticalCenter: parent ? parent.verticalCenter : undefined
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

        property var selectedNotes: Object()

        property int frets: +fretsComboBox.currentText + 1
        property int strings: +stringsComboBox.currentText
        property bool leftHanded: leftHandedCheckBox.checked

        onLeftHandedChanged: {
            // Force rebuilding the view. Otherwise the leftmost fret doesn't display well.
            visible = false;
            visible = true;
        }

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
            model: fretView.visible ? (fretView.frets * fretView.strings) : 0

            delegate: ItemDelegate {
                id: fretRect
                implicitWidth: 70 * Math.pow(0.96, fret)
                implicitHeight: 25

                property bool marked: !!fretView.selectedNotes[getFretIndex(str, fret)]

                property int str: Math.floor(model.index / fretView.frets)
                property int fret: fretView.leftHanded ? (fretView.frets - 1 - (model.index % fretView.frets)) : (model.index % fretView.frets)

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
                    Component.onCompleted: {
                        if (visible)
                            fretRect.setMarkerText()
                    }
                    onVisibleChanged: {
                        if (visible && !fretRect.marked)
                            fretRect.setMarkerText()
                    }
                }

                onMarkedChanged: setMarkerText()

                function setMarkerText() {
                    if (marked)
                        markerLoader.item.text = Qt.binding(function() { return fretView.selectedNotes[getFretIndex(str, fret)] || ""; });
                    else
                        markerLoader.item.text = fretplugin.guessNoteName(fretRect.str, fretRect.fret);
                }
            }
        }
    }
}
