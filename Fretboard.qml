import QtQuick 2.6
import QtQuick.Controls 2.1
import QtQuick.Window 2.2
import MuseScore 3.0

MuseScore {
    id: fretplugin
    menuPath: "Plugins.Fretboard"
    version:  "0.1.0"
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

    property var _CHORD_BY_TICK: ({})
    property var score: null
    property var cursor: null
    property var tuning: [64, 59, 55, 50, 45, 40, 0, 0, 0, 0] // default is 6-string classical guitar tuning

    property variant nameChord         : false
    property variant showNotesNames     : true  
    property variant showIntervals      : true  
    property variant showGuideTones     : false  
    property variant displayChordMode   : 0  //0: Normal chord C  F7  Gm  //1: Roman Chord level   Ⅳ
    property variant displayChordColor  : 1  //0: disable ,1 enable
    property variant inversion_notation : 1 //set to 1: bass note is specified after a / like that: C/E for first inversion C chord.
    property variant display_bass_note  : 0 //set to 1: bass note is specified after a / like that: C/E for first inversion C chord.

    property variant black : "#000000"
    property variant red       : "#ff0000"
    property variant green     : "#00ff00"
    property variant blue      : "#0000ff"
    property variant pale      : "#edf4ff"

    property variant color13th : "#ff00fb"    //color: ext.:(9/11/13)
    property variant color11th : "#9900ff"    //color: ext.:(9/11/13)
    property variant color9th  : "#ff0051"    //color: ext.:(9/11/13)
    property variant color7th  : "#00ccaa"    //color: 7th
    property variant color5th  : "#525252"    //color: 5th
    property variant color3rd  : "#007ecc"    //color: 3rd (4th for suss4)
    property variant colorroot : "#000000"    //color: Root

    property var inversions      : ["", " \u00B9", " \u00B2"," \u00B3"," \u2074"," \u2075"," \u2076"," \u2077"," \u2078"," \u2079"] // unicode for superscript "1", "2", "3" (e.g. to represent C Major first, or second inversion)
    property var inversions_7th  : inversions
    property var inversions_9th  : inversions
    property var inversions_11th : inversions
    property var inversions_13th : inversions
    property var chord_type : undefined
    property var chord_str : undefined

    property var _TPC_NOTE : ["Cbb","Gbb","Dbb","Abb","Ebb","Bbb",
        "Fb","Cb","Gb","Db","Ab","Eb","Bb","F","C","G","D","A","E","B","F#","C#","G#","D#","A#","E#","B#",
        "F##","C##","G##","D##","A##","E##","B##","Fbb"]; //tpc -1 is at number 34 (last item).

    property var _PITCH_NOTE : ["C","C#","D","D#","E","F","F#", "G", "G#", "A", "A#", "B"];

    function getPitch(string, fret) {
        return tuning[string] + fret;
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
        for (var i = 0; i < tuning.length; ++i)
            frets.push(-1);

        if (!chord) {
            fretView.selectedIndices = frets;
            return;
        }

        var notesArray = objToArray(chord.notes)

        //Add note from AddNoteTextField
        if (_TPC_NOTE.indexOf(addNoteTextField.text) >= 0) {
            notesArray.push({
                pitch: _PITCH_NOTE.indexOf(addNoteTextField.text),
                tpc: _TPC_NOTE.indexOf(addNoteTextField.text)
            });
        }

        
        var segment = findSegment(chord)
        if (segment) {
            var chordAnalisys = analiseSegment(cursor, segment, notesArray)
            //printChordAnalisys(chordAnalisys)
        }


        var fretNotes = []
        var notes = chord.notes;
        for (var i = 0; i < notes.length; ++i) {
            var n = notes[i];
            if (n.string > -1 && n.fret > -1) {
                n.chordIntervalName = notesArray[i].chordIntervalName || "??"
                n.noteName = notesArray[i].noteName || "??"
                frets[n.string] = n.fret
                fretNotes[n.string] = n
                //console.log("CHORD INTERVAL:", n.chordIntervalName, n.string)
            }
        }

        chordAnalisys.chord = chord
        fretView.fretNotes = fretNotes;
        fretView.selectedIndices = frets;
        fretView.chordAnalisys = chordAnalisys;
        return chord
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
        setConfig();
        updateCurrentScore();

        if (state.selectionChanged) {
            updateSelectedChord();
        }
    }

    onRun: {
        console.log("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n");
        setConfig();
        updateCurrentScore();
        updateSelectedChord();
        updateScoreChords(cursor, _CHORD_BY_TICK);
    }

    function setConfig() {
        setInversionNotation();
        setChordTypes();
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
        id: markerComponent
        Item {
            height: 20
            width: 45
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: rect.verticalCenter
                font.family: "Arial"
                font.pixelSize: 9
                color: "white"
                text: noteName
            }
            Rectangle {
                id: rect
                height: 18
                width: 18
                radius: 18
                anchors.alignWhenCentered: false
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.alignWhenCentered: false
                    anchors.horizontalCenter: rect.horizontalCenter
                    anchors.verticalCenter: rect.verticalCenter
                    font.family: "Arial"
                    font.pixelSize: 10
                    font.bold: true
                    fontSizeMode: Text.Fit
                    text: interval
                }
                color: "red"
            }
        }
    }

    Row {
        id: displaySettings

        anchors {
            left: fretSettings.right
            top: fretView.bottom
            leftMargin: 40
        }

        CheckBox {
            text: qsTranslate("action", "Name Chord")
            checked: nameChord
            indicator.width: 12
            indicator.height: 12
            onClicked: {
                nameChord = checked
                updateScoreChords(cursor, _CHORD_BY_TICK);
            }
        }

        CheckBox {
            text: qsTranslate("action", "Show Notes")
            checked: showNotesNames
            indicator.width: 12
            indicator.height: 12
            onClicked: {
                showNotesNames = checked
                updateScoreChords(cursor, _CHORD_BY_TICK);
            }
        }

        CheckBox {
            text: qsTranslate("action", "Show Intervals")
            checked: showIntervals
            indicator.width: 12
            indicator.height: 12
            onClicked: {
                showIntervals = checked
                updateScoreChords(cursor, _CHORD_BY_TICK);
            }
        }

        CheckBox {
            text: qsTranslate("action", "Show Guide Tones")
            checked: showGuideTones
            indicator.width: 12
            indicator.height: 12
            onClicked: {
                showGuideTones = checked
                updateScoreChords(cursor, _CHORD_BY_TICK);
            }
        }

        CheckBox {
            text: qsTranslate("action", "Key Notation")
            checked: displayChordMode
            indicator.width: 12
            indicator.height: 12
            onClicked: {
                displayChordMode = checked
                updateScoreChords(cursor, _CHORD_BY_TICK);
            }
        }

        CheckBox {
            text: qsTranslate("action", "Inversion Notation")
            checked: inversion_notation
            indicator.width: 12
            indicator.height: 12
            onClicked: {
                inversion_notation = checked
                updateScoreChords(cursor, _CHORD_BY_TICK);
            }
        }
        CheckBox {
            text: qsTranslate("action", "Bass Notation")
            checked: display_bass_note
            indicator.width: 12
            indicator.height: 12
            onClicked: {
                display_bass_note = checked
                updateScoreChords(cursor, _CHORD_BY_TICK);
            }
        }
        CheckBox {
            text: qsTranslate("action", "Chord Colors")
            checked: displayChordColor
            indicator.width: 12
            indicator.height: 12
            onClicked: {
                displayChordColor = checked
                updateScoreChords(cursor, _CHORD_BY_TICK);
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
        
        TextField {
            id: addNoteTextField
            width: parent.width
            placeholderText: qsTranslate("InspectorFretDiagram", "Add unplayed note:")
            //onEditingFinished:
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
                    top: parent ? parent.top : undefined
                    left: parent ? parent.left : undefined
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
                property string interval: "££"
                property string noteName: "££"
                sourceComponent: parent.hasTopHalfDot ? markerComponent : null
                anchors {
                    verticalCenter: parent ? parent.top : undefined
                    horizontalCenter: parent ? parent.horizontalCenter : undefined
                }
                onLoaded: {
                    if (item)
                        item.color = "black"
                }
            }
            Loader {
                property string interval: "££"
                property string noteName: "££"
                sourceComponent: parent.hasBottomHalfDot ? markerComponent : null
                anchors {
                    verticalCenter: parent ? parent.bottom : undefined
                    horizontalCenter: parent ? parent.horizontalCenter : undefined
                }
                onLoaded: {
                    if (item)
                        item.color = "black"
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
                    top: parent ? parent.top : undefined
                    right: parent ? parent.right : undefined
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

        property var selectedIndices: []
        property var fretNotes: []
        property var chordAnalisys: {}

        property int frets: +fretsComboBox.currentText + 1
        property int strings: +stringsComboBox.currentText

        columns: frets
        rows: strings

        property var dots: [3, 5, 7, 9, 15, 17, 19, 21]
        property var doubleDots: [12, 24]

        function hasDot(string, fret) {
            return false;
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
                    property string interval: showIntervals  && fretView.fretNotes[str] ? fretView.fretNotes[str].chordIntervalName : ''
                    property string noteName: showNotesNames && fretView.fretNotes[str] ? fretView.fretNotes[str].noteName : ''
                    sourceComponent: markerComponent
                    anchors.centerIn: parent
                    visible: fretRect.marked
                }
            }
        }
    }
// ==========================================================================================
// ==========================================================================================
// ==========================================================================================
// ==========================================================================================
// ==========================================================================================
// ==========================================================================================
// ==========================================================================================
// ==========================================================================================
// ==========================================================================================

    
    // ---------- get note name from TPC (Tonal Pitch Class):
    function getNoteName(note_tpc){ 
        var notename = "";
        if(note_tpc != 'undefined' && note_tpc<=33){
            if(note_tpc==-1) 
                notename=_TPC_NOTE[34];
            else
                notename=_TPC_NOTE[note_tpc];
        }
        return notename;
    }
// Roman numeral sequence for chords ①②③④⑤⑥⑦  Ⅰ  Ⅱ Ⅲ  Ⅳ  Ⅴ Ⅵ   Ⅶ Ⅷ Ⅸ Ⅹ Ⅺ Ⅻ
    function getNoteRomanSeq(note,keysig){
        var notename = "";
        var num=0;
        var keysigNote = [11,6,1,8,3,10,5,0,7,2,9,4,11,6,1];
        var Roman_str_flat_mode1 = ["Ⅰ","Ⅱ♭","Ⅱ","Ⅲ♭","Ⅲ","Ⅳ","Ⅴ♭","Ⅴ","Ⅵ♭","Ⅵ","Ⅶ♭","Ⅶ"];
        var Roman_str_flat_mode2 =  ["①","②♭","②","③♭","③","④","⑤♭","⑤","⑥♭","⑥","⑦♭","⑦"];

        if(keysig != 'undefined' ){
            num=(note+12-keysigNote[keysig+7])%12;
            notename=Roman_str_flat_mode1[num];

        }
        //console.log("keysigNote num:"+note + " "+ keysig + " "+notename);
        return notename;
    }

    function string2Roman(str){
        var strtmp="";
        strtmp=str[0];
        if(str.length>1 && str[1]=="♭")
            strtmp+=str[1];
        var Roman_str_flat_mode1 = ["Ⅰ","Ⅱ♭","Ⅱ","Ⅲ♭","Ⅲ","Ⅳ","Ⅴ♭","Ⅴ","Ⅵ♭","Ⅵ","Ⅶ♭","Ⅶ"];
        var Roman_str_flat_mode2 =  ["①","②♭","②","③♭","③","④","⑤♭","⑤","⑥♭","⑥","⑦♭","⑦"];
        var i=0;
        for(;i<Roman_str_flat_mode1.length;i++)
            if(strtmp==Roman_str_flat_mode1[i])
                return i;

        return -1;
    }    
    // ---------- remove duplicate notes from chord (notes with same pitch) --------
    function remove_dup(chord){
        var chord_notes=new Array();

        for(var i=0; i<chord.length; i++)
            chord_notes[i] = chord[i].pitch%12; // remove octaves

        chord_notes.sort(function(a, b) { return a - b; }); //sort notes

        var chord_uniq = chord_notes.filter(function(elem, index, self) {
            return index == self.indexOf(elem);
        }); //remove duplicates

        return chord_uniq;
    }
    
    // ---------- find intervals for all possible positions of the root note ---------- 
    function find_intervals(chord_uniq){
        var n=chord_uniq.length;
        var intervals = new Array(n); for(var i=0; i<n; i++) intervals[i]=new Array();

        for(var root_pos=0; root_pos<n; root_pos++){ //for each position of root note in the chord
            var idx=-1;
            for(var i=0; i<n-1; i++){ //get intervals from current "root"
                var cur_inter = (chord_uniq[(root_pos+i+1)%n] - chord_uniq[(root_pos+i)%n])%12;  while(cur_inter<0) cur_inter+=12;
                if(cur_inter != 0){// && (idx==-1 || intervals[root_pos][idx] != cur_inter)){   //avoid duplicates and 0 intervals
                    idx++;
                    intervals[root_pos][idx]=cur_inter;
                    if(idx>0)
                        intervals[root_pos][idx]+=intervals[root_pos][idx-1];
                }
            }
            //console.log('\t intervals: ' + intervals[root_pos]);
        }

        return intervals;
    }
    
    function compare_arr(ref_arr, search_elt) { //returns an array of size ref_tab.length
        if (ref_arr == null || search_elt == null) return [];
        var cmp_arr=[], nb_found=0;
        for(var i=0; i<ref_arr.length; i++){
            if( search_elt.indexOf(ref_arr[i]) >=0 ){
                cmp_arr[i]=1;
                nb_found++;
            }else{
                cmp_arr[i]=0;
            }
        }
        return {
            cmp_arr: cmp_arr,
            nb_found: nb_found
        };
    }

    function setInversionNotation() {
      //var INVERSION_NOTATION = 0; //set to 0: inversions are not shown
                                    //set to 1: inversions are noted with superscript 1, 2 or 3
                                    //set to 2: figured bass notation is used instead
                                
       //var DISPLAY_BASS_NOTE = 0; //set to 1: bass note is specified after a / like that: C/E for first inversion C chord.
 
        //Standard notation for inversions:
        if(inversion_notation===1){
            inversions = ["", " \u00B9", " \u00B2"," \u00B3"," \u2074"," \u2075"," \u2076"," \u2077"," \u2078"," \u2079"]; // unicode for superscript "1", "2", "3" (e.g. to represent C Major first, or second inversion)
            inversions_7th = inversions;
			inversions_9th  = inversions;
			inversions_11th = inversions;
			inversions_13th = inversions;

        }else if(inversion_notation===2){//Figured bass of inversions:
            inversions = ['', ' \u2076', ' \u2076\u2084','','','','','','',''];
            inversions_7th = [' \u2077', ' \u2076\u2085', ' \u2074\u2083', ' \u2074\u2082', ' \u2077-\u2074', ' \u2077-\u2075', ' \u2077-\u2076', ' \u2077-\u2077', ' \u2077-\u2078', ' \u2077-\u2079'];
			inversions_9th = [' \u2079', ' inv\u00B9', ' inv\u00B2', ' inv\u00B3',' inv\u2074',' inv\u2075',' inv\u2076',' inv\u2077',' inv\u2078',' inv\u2079'];
			inversions_11th = [' \u00B9\u00B9', ' inv\u00B9', ' inv\u00B2', ' inv\u00B3',' inv\u2074',' inv\u2075',' inv\u2076',' inv\u2077',' inv\u2078',' inv\u2079'];
            inversions_13th = [' \u00B9\u00B3', ' inv\u00B9', ' inv\u00B2', ' inv\u00B3',' inv\u2074',' inv\u2075',' inv\u2076',' inv\u2077',' inv\u2078',' inv\u2079'];
        }else{
            inversions      = ["","","","","","","","","",""]; 
			inversions_7th  = [" \u2077","","","","","","","","",""]; 
			inversions_9th  = [" \u2079","","","","","","","","",""]; 
			inversions_11th = [" \u00B9\u00B9","","","","","","","","",""]; 
			inversions_13th = [" \u00B9\u00B3","","","","","","","","",""]; 
        }        
    }

    function setChordTypes() {
        // intervals (number of semitones from root note) for main chords types...          //TODO : revoir fonctionnement et identifier d'abord triad, puis seventh ?
        //          0    1   2    3        4   5          6      7    8         9     10    11
        // numeric: R,  b9,  9,  m3(#9),  M3, 11(sus4), #11(b5), 5,  #5(b13),  13(6),  7,   M7  //Ziya
        chord_type = [  [4,7],          //00: M (0)*
                            [3,7],          //01: m*
                            [3,6],          //02: dim*
                            [5,7],          //03: sus4 = Suspended Fourth*
                            [5,7,10],       //04: 7sus4 = Dominant7, Suspended Fourth*
                            [4,7,11],       //05: M7 = Major Seventh*
                            [3,7,11],       //06: mMa7 = minor Major Seventh*
                            [3,7,10],       //07: m7 = minor Seventh*
                            [4,7,10],       //08: m7 = Dominant Seventh*
                            [3,6,9],        //09: dim7 = Diminished Seventh*
                            [4,8,11],       //10: #5Maj7 = Major Seventh, Raised Fifth*
                            [4,8,10],       //11: #57 = Dominant Seventh, Raised Fifth*
                            [4,8],          //12: #5 = Majör Raised Fifth*
                            [3,6,10],       //13: m7b5 = minor 7th, Flat Fifth*
                            [4,6,10],       //14: M7b5 = Major 7th, Flat Fifth*                     
                            [4,7,2],        //15: add9 = Major additional Ninth*
                            [4,7,11,2],     //16: Maj7(9) = Major Seventh, plus Ninth*
                            [4,7,10,2],     //17: 7(9) = Dominant Seventh, plus Ninth*
                            [3,7,2],        //18: add9 = minor additional Ninth*
                            [3,7,11,2],     //19: m9(Maj7) = minor Major Seventh, plus Ninth*
                            [3,7,10,2],     //20: m7(9) = minor Seventh, plus Ninth*
                            [4,7,11,6],     //21: Maj7(#11) = Major Seventh, Sharp Eleventh*
                            [4,7,11,2,6],   //22: Maj9(#11) = Major Seventh, Sharp Eleventh, plus Ninth*
                            [4,7,10,6],     //23: 7(#11) =  Dom. Seventh, Sharp Eleventh*
                            [4,7,10,2,6],   //24: 9(#11) =  Dom. Seventh, Sharp Eleventh, plus Ninth*
                            [4,7,10,9],     //25: 7(13) =  Dom. Seventh, Thirteenth*
                            [4,7,10,2,9],   //26: 9(13) =  Dom. Seventh, Thirteenth, plus Ninth*
                            [4,7,10,1],     //27: 7(b9) = Dominant Seventh, plus Flattened Ninth*
                            [4,7,10,8],     //28: 7(b13) =  Dom. Seventh, Flattened Thirteenth*
                            [4,7,10,1,8],   //29: 7(b13b9) =  Dom. Seventh, Flattened Thirteenth, plus Flattened Ninth*
                            [4,7,10,1,5,8], //30: 7(b13b911) =  Dom. Seventh, Flattened Thirteenth plus Flattenet Ninth, plus Eleventh*
                            [4,7,10,3],     //31: 7(#9) = Dominant Seventh, plus Sharp Ninth*
                            [3,7,10,5],     //32: m7(11) = minor Seventh, plus Eleventh*
                            [3,7,10,2,5],   //33: m9(11) = minor Seventh, plus Eleventh, plus Ninth*
                            [0,0,0]];       //34: Dummy
                                               
        //Notice: [2,7],     //sus2  = Suspended Two // Not recognized; Recognized as 5sus/1 eg. c,d,g = Gsus4/C
        //Notice: [4,7,9],   //6  = Sixth // Not recognized; Recognized as vim7/1 eg. c,e,g,a = Am7/C
        //Notice: [3,7,9],   //m6 = Minor Sixth // Not recognized; Recognized as vim7b5/1 eg. c,e,g,a = Am7b5/C
        //Notice: [4,7,9,2], //6(9) = Nine Sixth //Removed; clashed with m7(11)
        //Notive: [7],       //1+5 //Removed; has some problems
                            
                            //... and associated notation:
        //var chord_str = ["", "m", "\u00B0", "MM7", "m7", "Mm7", "\u00B07"];
        chord_str = ["", "m", "dim", "sus4",  "7sus4", "Maj7", "m(Maj7)", "m7", "7", "dim7", "Maj7(#5)", "7(#5)", "(#5)", "m7(b5)", "7(b5)", "(add9)", "Maj9", "9", "m(add9)", "m9(Maj7)", "m9", "Maj7(#11)", "Maj9(#11)", "7(#11)", "9(#11)", "7(13)", "9(13)", "7(b9)","7(b13)", "7(b9/b13)", "11(b9/b13)", "7(#9)", "m7(11)", "m11", "x"];
        /*var chord_type_reduced = [ [4],  //M
                                    [3],  //m
                                    [4,11],   //MM7
                                    [3,10],   //m7
                                    [4,10]];  //Mm7
        var chord_str_reduced = ["", "m", "MM", "m", "Mm"];*/
        /*var major_scale_chord_type = [[0,3], [1,4], [1,4], [0,3], [0,5], [1,4], [2,6]]; //first index is for triads, second for seventh chords.
        var minor_scale_chord_type = [[0,4], [2,6], [0,3], [1,4], [0,5], [0,3], [2,6]];*/


    }
        
    function getChordName(chordNotes) {
        var analisys = ({})    
        analisys.rootNote = null;
        analisys.inversion = null;
        analisys.keySignature = cursor.keySignature;
        analisys.seventhchord=0;
        analisys.chordName='';

        // FIRST we get all notes on current position of the cursor, for all voices and all staves.
        if(chordNotes.length < 1) return analisys;

        var notesArray = objToArray(chordNotes);
               
        // ---------- SORT CHORD from bass to soprano --------
        notesArray.sort(function(a, b) { return (a.pitch) - (b.pitch); }); //bass note is now chord[0]
        
        //debug:
//        for(var i=0; i<chord.length; i++){
//            console.log('pitch note ' + i + ': ' + chord[i].pitch + ' -> ' + chord[i].pitch%12);
//        }   
        
        analisys.chord_uniq = remove_dup(notesArray); //remove multiple occurence of notes in chord
        analisys.intervals = find_intervals(analisys.chord_uniq);
        
        //debug:
        //for(var i=0; i<analisys.chord_uniq.length; i++) console.log('pitch note ' + i + ': ' + analisys.chord_uniq[i]);
        // console.log('compare: ' + compare_arr([0,1,2,3,4,5],[1,3,4,2])); //returns [0,1,1,1,1,0}
        
        
        // ---------- Compare analisys.intervals with chord types for identification ---------- 
        var idx_chtype=-1, idx_rootpos=-1, nb_found=0;
        var idx_chtype_arr=[], idx_rootpos_arr=[], cmp_result_arr=[];
        for(var idx_chtype_=0; idx_chtype_<chord_type.length; idx_chtype_++){ //chord types. 
            for(var idx_rootpos_=0; idx_rootpos_<analisys.intervals.length; idx_rootpos_++){ //loop through the analisys.intervals = possible root positions
                var cmp_result = compare_arr(chord_type[idx_chtype_], analisys.intervals[idx_rootpos_]);
                if(cmp_result.nb_found>0){ //found some analisys.intervals
                    if(cmp_result.nb_found == chord_type[idx_chtype_].length){ //full chord found!
                        if(cmp_result.nb_found>nb_found){ //keep chord with maximum number of similar interval
                            nb_found=cmp_result.nb_found;
                            idx_rootpos=idx_rootpos_;
                            idx_chtype=idx_chtype_;
                        }
                    }
                    idx_chtype_arr.push(idx_chtype_); //save partial results
                    idx_rootpos_arr.push(idx_rootpos_);
                    cmp_result_arr.push(cmp_result.cmp_arr);
                }
            }
        }
        
        if(idx_chtype<0 && idx_chtype_arr.length>0){ //no full chord found, but found partial chords
            console.log('other partial chords: '+ idx_chtype_arr);
            console.log('root_pos: '+ idx_rootpos_arr);
            console.log('cmp_result_arr: '+ cmp_result_arr);

            for(var i=0; i<cmp_result_arr.length; i++){
                if(cmp_result_arr[i][0]===1 && cmp_result_arr[i][2]===1){ //third and 7th ok (missing 5th)
                    idx_chtype=idx_chtype_arr[i];
                    idx_rootpos=idx_rootpos_arr[i];
                    console.log('3rd + 7th OK!');
                    break;
                }
            }
            if(idx_chtype<0){ //still no chord found. Check for third interval only (missing 5th and 7th)
                for(var i=0; i<cmp_result_arr.length; i++){
                    if(cmp_result_arr[i][0]===1){ //third ok 
                        idx_chtype=idx_chtype_arr[i];
                        idx_rootpos=idx_rootpos_arr[i];
                        console.log('3rd OK!');
                        break;
                    }
                }
            }
        }
                
		if(idx_chtype>=0){
            if (idx_chtype == 1 || idx_chtype == 2 || idx_chtype == 3 || idx_chtype == 12 ) {
				analisys.seventhchord=0;
			} else if ((idx_chtype >= 4 && idx_chtype <=11) || idx_chtype == 13 || idx_chtype == 14 ) {
			analisys.seventhchord=1;  //7th
			} else if ((idx_chtype >= 15 && idx_chtype <=20) || idx_chtype == 27 || idx_chtype == 31 ) {
			analisys.seventhchord=2; //9th
			} else if ((idx_chtype >= 21 && idx_chtype <=24) || idx_chtype == 32 || idx_chtype == 33) {
			analisys.seventhchord=3; //11th
			} else if (idx_chtype == 25 || idx_chtype ==26 || idx_chtype == 28 || idx_chtype == 29 || idx_chtype == 30 ) {
			analisys.seventhchord=4; //13th
			}
			analisys.rootNote=analisys.chord_uniq[idx_rootpos];
            //console.log('CHORD type:', idx_chtype, 'root_pos:', idx_rootpos, 'rootNote:', analisys.rootNote, 'seventhchord:', analisys.seventhchord, 'intervals', analisys.intervals[idx_rootpos]);
        }else{
            console.log('No chord found');
        }

        return analiseChordNames(analisys, chordNotes, idx_chtype);
    }

    function analiseChordNames(analisys, chord, idx_chtype) {
        var regular_chord=[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]; //without NCTs
        var bass=null; 
        analisys.chordNameRoman='';
        if (analisys.rootNote !== null) { // ----- the chord was identified
            for(i=0; i<chord.length; i++){  // ---- color notes and find root note
                if((chord[i].pitch%12) === (analisys.rootNote%12)){  //color root note
                    regular_chord[0] = chord[i];
                    if(bass==null) bass=chord[i];
                }else if((chord[i].pitch%12) === ((analisys.rootNote+chord_type[idx_chtype][0])%12)){ //third note
                    regular_chord[1] = chord[i];
                    if(bass==null) bass=chord[i];
                }else if(chord_type[idx_chtype].length>=2 && (chord[i].pitch%12) === ((analisys.rootNote+chord_type[idx_chtype][1])%12)){ //5th
                    regular_chord[2] = chord[i];
                    if(bass==null) bass=chord[i];
                }else if(chord_type[idx_chtype].length>=6 && (chord[i].pitch%12) === ((analisys.rootNote+chord_type[idx_chtype][5])%12)){ //13Other
                    regular_chord[6] = chord[i];
                    if(bass==null) bass=chord[i];
                    //analisys.seventhchord=4;
                }else if(chord_type[idx_chtype].length>=5 && (chord[i].pitch%12) === ((analisys.rootNote+chord_type[idx_chtype][4])%12)){ //11Other
                    regular_chord[5] = chord[i];
                    if(bass==null) bass=chord[i];
                    //analisys.seventhchord=3;
                }else if(chord_type[idx_chtype].length>=4 && (chord[i].pitch%12) === ((analisys.rootNote+chord_type[idx_chtype][3])%12)){ //9Other
                    regular_chord[4] = chord[i];
                    if(bass==null) bass=chord[i];
                    //analisys.seventhchord=2;
                }else if(chord_type[idx_chtype].length>=3 && (chord[i].pitch%12) === ((analisys.rootNote+chord_type[idx_chtype][2])%12)){ //7th
                    regular_chord[3] = chord[i];
                    if(bass==null) bass=chord[i];
                    //analisys.seventhchord=1;
                }else{      //reset other note color 
				    //analisys.seventhchord='';
                    chord[i].color = black; 
                }
                chord[i].semitones = chord[i].pitch-analisys.rootNote
                chord[i].noteName = getNoteName(chord[i].tpc)
                chord[i].color = semitonesToColor(chord[i].semitones)

                var n = semitonesToInterval(chord[i].semitones);
                if (!(n == 'b3' || n == '3' || n == 'b7' || n == '7')) chord[i].guideTone = true
                chord[i].chordIntervalName = n

                if (showGuideTones) {
                    if (chord[i].guideTone) chord[i].visible = false
                } else {
                    if (chord[i].guideTone) chord[i].visible = true
                }
            }
        
            // ----- find root note //commentted before: Ziya
            for(var i=0; i<chord.length; i++){
                if(chord[i].pitch%12 == analisys.rootNote)
                    analisys.chordRootLNote = chord[i];
            }
            
            // ----- find chord name:
            var rootNoteName = getNoteName(regular_chord[0].tpc);
            analisys.chordName = rootNoteName + chord_str[idx_chtype];
            analisys.chordNameRoman = getNoteRomanSeq(regular_chord[0].pitch,analisys.keySignature);
            analisys.chordNameRoman += chord_str[idx_chtype];

        } else {
            for(i=0; i<chord.length; i++){
                chord[i].color = black; 
            }
        }

        // ----- find analisys.inversion
        inv=-1;
        if (analisys.chordName !== ''){ // && analisys.inversion !== null) {
            var bass_pitch=bass.pitch%12;
            //console.log('bass_pitch: ' + bass_pitch);
            if(bass_pitch == analisys.rootNote){ //Is chord in root position ?
                inv=0;
            }else{
                for(var inv=1; inv<chord_type[idx_chtype].length+1; inv++){
                   if(bass_pitch == ((analisys.rootNote+chord_type[idx_chtype][inv-1])%12)) break;
                   //console.log('note n: ' + ((chord[idx_rootpos].pitch+analisys.intervals[idx_rootpos][inv-1])%12));
                }
            }            
            
            // Commented: Both are fixed now -Ziya.
            
            if (inversion_notation===1 || inversion_notation===2 ) {
            if(analisys.seventhchord == 0){ //we have a triad:
                analisys.chordName += inversions[inv]; //no inversions for this version.
            analisys.chordNameRoman += inversions[inv]; //no inversions for this version.
            }else{  //we have a 7th chord 
                if (analisys.seventhchord===4) {
				analisys.chordName += inversions_13th[inv]; 
            analisys.chordNameRoman += inversions_13th[inv];
				} else if (analisys.seventhchord===3) {
				analisys.chordName += inversions_11th[inv]; 
            analisys.chordNameRoman += inversions_11th[inv];
				} else if (analisys.seventhchord===2) {
				analisys.chordName += inversions_9th[inv]; 
            analisys.chordNameRoman += inversions_9th[inv];
				} else if (analisys.seventhchord===1) {
				analisys.chordName += inversions_7th[inv]; 
            analisys.chordNameRoman += inversions_7th[inv];
				}
            } 
            }
            
           // if(bassMode===1 && inv>0){
             if(display_bass_note==1 && inv>0){
                analisys.chordName+="/"+getNoteName(bass.tpc);
            }
            
            if(displayChordMode === 1 ) {
                analisys.chordNamanalisys.chordNameRoman;
            } else if(displayChordMode === 2 ) {
                analisys.chordName += analisys.chordNameRoman
            }

            analisys.bassNote = bass
            analisys.inversion = inv
        }
        return analisys;
    }

    function semitonesToInterval(semitones) {
        semitones = Math.abs(semitones)%12
        if (semitones == 0) return "R"
        if (semitones == 1) return "b9"
        if (semitones == 2) return "9"
        if (semitones == 3) return "b3"
        if (semitones == 4) return "3"
        if (semitones == 5) return "11"
        if (semitones == 6) return "b5"
        if (semitones == 7) return "5"
        if (semitones == 8) return "b13"
        if (semitones == 9) return "13"
        if (semitones == 10) return "b7"
        if (semitones == 11) return "7"
        if (semitones == 12) return "R"
    }

    function semitonesToColor(semitones) {
        semitones = Math.abs(semitones)%12
        if (!displayChordColor) return black
        if (semitones == 0) return colorroot
        if (semitones == 1) return color9th
        if (semitones == 2) return color9th
        if (semitones == 3) return color3rd
        if (semitones == 4) return color3rd
        if (semitones == 5) return color11th
        if (semitones == 6) return color11th
        if (semitones == 7) return color5th
        if (semitones == 8) return color13th
        if (semitones == 9) return color13th
        if (semitones == 10) return color7th
        if (semitones == 11) return color7th
        if (semitones == 12) return colorroot
    }


    function printChordAnalisys(analisys) {      
        var bassNote = analisys.bassNote
        var chordRootLNote = analisys.chordRootLNote
        analisys.bassNote = null
        analisys.chordRootLNote = null
        console.log("CHORD ANALISYS: ", JSON.stringify(analisys))            
        analisys.bassNote = bassNote
        analisys.chordRootLNote = chordRootLNote
    }
    
    function getSegmentHarmony(segment) {
        //if (segment.segmentType != Segment.ChordRest) 
        //    return null;
        var aCount = 0;
        var annotation = segment.annotations[aCount];
        while (annotation) {
            if (annotation.type == Element.HARMONY)
                return annotation;
            annotation = segment.annotations[++aCount];     
        }
        return null;
    } 
    
    function getAllCurrentNotes(selection){
        var full_chord = [];
        var idx_note=0;
        var cursor = selection.cursor
        for (var staff = selection.endStaff; staff >= selection.startStaff; staff--) {
            for (var voice = 8; voice >=0; voice--) { //Ziya var voice = 3 New! var voice = 6
                cursor.voice = voice;
                cursor.staffIdx = staff;
                if (cursor.element && cursor.element.type == Element.CHORD) {
                    var notes = cursor.element.notes;
                    for (var i = 0; i < notes.length; i++) {
                          full_chord[idx_note]=notes[i];
                          idx_note++;
                    }
                }
            }
        }
        return full_chord;
    }

    function objToArray(notes) {
        var notesArray = [];
        for (var i = 0; i < notes.length; i++) {
            notesArray[i]=notes[i];
        }
        return notesArray
    }
    
    function setCursorToTime(cursor, time){
        var cur_staff=cursor.staffIdx;
        cursor.rewind(0);
        cursor.staffIdx=cur_staff;
        while (cursor.segment && cursor.tick < curScore.lastSegment.tick + 1) { 
            var current_time = cursor.tick;
            if(current_time>=time){
                return true;
            }
            cursor.next();
        }
        cursor.rewind(0);
        cursor.staffIdx=cur_staff;
        return false;
    }
    
    function next_note(cursor, startStaff, endStaff){
        var cur_time=cursor.tick;
        console.log('cur_time: ' + cur_time);
        var next_time=-1;
        var cur_staff=startStaff;
        for (var staff = startStaff; staff <= endStaff; staff++) {
            //for (var voice = 0; voice < 4; voice++) {
                //cursor.voice=0;
            cursor.staffIdx = staff;
            setCursorToTime(cursor, cur_time);
            cursor.next();
            console.log('tick: ' + cursor.tick);
            if((next_time<0 || cursor.tick<next_time) && cursor.tick !=0) {
                next_time=cursor.tick;
                cur_staff=staff;
            }
            //}
        }
        console.log('next_time: ' + next_time);
        cursor.staffIdx = cur_staff;
        //cursor.next();
        if(next_time>0 && cursor.tick != next_time){
            setCursorToTime(cursor, next_time);
        }
    }

    function analiseSegment(cursor, segment, chordNotes) {
        var prev_chordName = undefined;
        var analisys = getChordName(chordNotes);

        if (nameChord === true && analisys.chordName !== '') { //chord has been identified
            var harmony = getSegmentHarmony(segment);
            if (harmony) { //if chord symbol exists, replace it
                //console.log("got harmony " + staffText + " with root: " + harmony.rootTpc + " bass: " + harmony.baseTpc);
                harmony.text = analisys.chordName;
            }else{ //chord symbol does not exist, create it
                harmony = newElement(Element.HARMONY);
                harmony.text = analisys.chordName;
                //console.log("text type:  " + staffText.type);
                cursor.add(harmony);
            }
            
            if(prev_chordName == analisys.chordName){// && isEqual(prev_full_chord, full_chord)){ //same chord as previous one ... remove text symbol
                harmony.text = '';
            }
            //console.log("xpos: "+harmony.pos.x+" ypos: "+harmony.pos.y);
            /*staffText = newElement(Element.STAFF_TEXT);
            staffText.text = analisys.chordName;
            staffText.pos.x = 0;
            cursor.add(staffText);*/
        }
        return analisys
    }    

    function getStaffSelection(cursor) {

        if (!cursor.segment) { // no selection
            return {
                fullScore: true,
                startStaff: 0, // start with 1st staff
                endStaff: curScore.nstaves - 1, // and end with last
                cursor: cursor
            }
        }
        
        var selection = ({});
        selection.startStaff = cursor.staffIdx;
        cursor.rewind(2);
        if (cursor.tick === 0) {
            // this happens when the selection includes
            // the last measure of the score.
            // rewind(2) goes behind the last segment (where
            // there's none) and sets tick=0
            selection.endTick = curScore.lastSegment.tick + 1;
        } else {
            selection.endTick = cursor.tick;
        }
        selection.endStaff = cursor.staffIdx;
        selection.fullScore = false
        selection.cursor = cursor


        // console.log(startStaff + " - " + endStaff + " - " + endTick);
        // console.log('startStaff: ' + startStaff);
        // console.log('endStaff: ' + endStaff);
        // console.log('curScore.nstaves: ' + curScore.nstaves);
        // console.log('endTick: ' + endTick);
        // console.log('cursor.tick: ' + cursor.tick);
        // console.log('curScore.lastSegment.tick: ' + curScore.lastSegment.tick);

        return selection;
    }

    function updateScoreChords(cursor, chordByTickDict) {        
        if (!cursor) return;

        var selection = getStaffSelection(cursor)
                
        cursor.rewind(1); // beginning of selection
        if (selection.fullScore) { // no selection
            cursor.rewind(0); // beginning of score
        }
        cursor.voice = 0;
        cursor.staffIdx = selection.startStaff; //staff;
        var keySig = cursor.keySignature;
        var keysig_name_major = getNoteName(keySig+7+7);
        var keysig_name_minor = getNoteName(keySig+7+10);
        console.log('559: keysig: ' + keySig + ' -> '+keysig_name_major+' major or '+keysig_name_minor+' minor.');
        
        var segment;
        var chordName = '';
        while ((segment=cursor.segment) && (selection.fullScore || cursor.tick < selection.endTick)) { //loop through the selection
            var chordNotes = getAllCurrentNotes(selection);        
            chordByTickDict[segment.tick] = analiseSegment(cursor, cursor.segment, chordNotes)
            //printChordAnalisys(chordByTickDict[segment.tick])    
            chordName = chordByTickDict[segment.tick].chordName
            cursor.next();
            //next_note(cursor, startStaff, endStaff);
        }
        
        if (selection.fullScore) analiseLastChordForSchoreKey(chordName, keysig_name_major, keysig_name_minor)
    }

    function analiseLastChordForSchoreKey(chordName, keysig_name_major, keysig_name_minor) {
        var key_str='';
        if(chordName==keysig_name_major){   //if last chord of score is a I chord => we most probably found the key :-)
            key_str=keysig_name_major+' major';
        }else if(chordName==keysig_name_minor){
            key_str=keysig_name_minor+' minor';
        }else{
            console.log('Key not found :-(');
        }
        if(key_str!=''){
            console.log('612: FOUND KEY: '+key_str);
                            
            /*var staffText = newElement(Element.STAFF_TEXT);
            staffText.text = key_str+':';
            staffText.pos.x = -13;
            staffText.pos.y = -1.5;
            cursor.rewind(0);
            cursor.add(staffText);*/
        }
    }
}
