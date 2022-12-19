import QtQuick 2.9
import MuseScore 3.0

MuseScore {
    id: plugin
    version:  "0.5.0"
    description: "Simple guitar fretboard to visualise and edit tablature scores"
    requiresScore: compatibility.useApi4

    implicitWidth: fretLoader.item ? fretLoader.item.implicitWidth : 0
    implicitHeight: fretLoader.item ? fretLoader.item.implicitHeight : 0

    QtObject {
        id: compatibility

        readonly property bool useApi4: mscoreVersion >= 40000
    }

    Component.onCompleted: {
        if (compatibility.useApi4) {
            plugin.title = "Fretboard";
            plugin.categoryCode = "note-input";
        } else {
            plugin.menuPath = "Plugins.Fretboard";
            plugin.pluginType = "dock";
            plugin.dockArea = "bottom";
        }
    }

    readonly property string pluginPanelObjectName: "FretPluginPanel"
    readonly property var fretboard: pluginDockPanel ? pluginDockPanel.fretboard : fretLoader.item
    property var pluginDockPanel: null

    Loader {
        id: fretLoader
        source: compatibility.useApi4 ? "" : "FretboardComponent.qml"
        onLoaded: item.mscore = plugin
    }

    function findChild(item, objectName) {
        var children = item.children;

        for (var i = 0; i < children.length; ++i) {
            if (children[i].objectName == objectName) {
                return children[i];
            }

            var obj = findChild(children[i], objectName);

            if (obj) {
                return obj;
            }
        }

        return null;
    }

    function addPluginToDockMU4() {
        var root = ui.rootItem;
        var windowContent = findChild(root, "WindowContent");
        var notationPage = null;

        if (windowContent) {
            for (var i = 0; i < windowContent.pages.length; ++i) {
                var page = windowContent.pages[i];

                if (page.objectName == "Notation") {
                    notationPage = page;
                    break;
                }
            }
        }

        if (notationPage) {
            pluginDockPanel = null;
            var pianoKeyboard = null;
            var pianoKeyboardObjectName = notationPage.pageModel.pianoKeyboardPanelName();

            for (var i = 0; i < notationPage.panels.length; ++i) {
                var panel = notationPage.panels[i];

                if (panel.objectName == pluginPanelObjectName) {
                    pluginDockPanel = panel;
                } else if (panel.objectName == pianoKeyboardObjectName) {
                    pianoKeyboard = panel;
                }
            }

            if (!pluginDockPanel) {
                var pluginDockComponent = Qt.createComponent("MU4FretboardDockPanel.qml");
                pluginDockPanel = pluginDockComponent.createObject(notationPage, {root: notationPage, mscore: plugin});
                notationPage.panels.push(pluginDockPanel);
            }

            var alreadyVisible = pluginDockPanel.visible;

            if (pianoKeyboard) {
                var wasPianoKeyboardHidden = !pianoKeyboard.visible;

                // Need to show a dock widget at the bottom. Otherwise our dock widget would start with a floating state.
                if (wasPianoKeyboardHidden) {
                    cmd("toggle-piano-keyboard");
                }

                var pluginDockPanelObjectName = pluginDockPanel.objectName;
                pianoKeyboard.objectName = "tmp";
                pluginDockPanel.objectName = pianoKeyboardObjectName;

                if (alreadyVisible) {
                    // Toggle twice to bring the plugin to the top.
                    cmd("toggle-piano-keyboard");
                }
                cmd("toggle-piano-keyboard");

                pluginDockPanel.objectName = pluginDockPanelObjectName;
                pianoKeyboard.objectName = pianoKeyboardObjectName;

                if (wasPianoKeyboardHidden) {
                    cmd("toggle-piano-keyboard");
                }

                fretboard.onRun();
            }
        }
    }

    // MuseScore 4 doesn't yet emit the scoreStateChanged signal,
    // so update state periodically in a certain interval instead.
    Timer {
        id: updateTimer
        interval: 33 // ms
        repeat: true
        onTriggered: fretboard.updateState(true)

        function updateState() {
            if (fretboard.mscore == plugin && fretboard.visible && Qt.application.state == Qt.ApplicationActive) {
                start();
            } else {
                stop();
            }
        }
    }

    Connections {
        target: fretboard
        enabled: compatibility.useApi4
        onVisibleChanged: updateTimer.updateState()
    }

    Connections {
        target: Qt.application
        enabled: compatibility.useApi4
        onStateChanged: updateTimer.updateState()
    }

    onScoreStateChanged: {
        if (compatibility.useApi4) {
            // MuseScore 4 doesn't yet provide this signal, no handling for now.
        } else {
            fretboard.updateState(state.selectionChanged);
        }
    }

    onRun: {
        if (compatibility.useApi4) {
            addPluginToDockMU4();
        }

        fretboard.onRun();
    }
}
