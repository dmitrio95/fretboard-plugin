import Muse.Dock 1.0 as MUDock

MUDock.DockPanelView {
    id: dockPanelView

    property var root: null
    property var mscore: null
    readonly property var fretboard: fretcomponent

    objectName: pluginPanelObjectName
    title: "Fretboard"

    height: fretcomponent.implicitHeight
    minimumHeight: root.horizontalPanelMinHeight
    maximumHeight: root.horizontalPanelMaxHeight

    groupName: root.horizontalPanelsGroup

    visible: false

    location: MUDock.Location.Bottom

    dropDestinations: root.horizontalPanelDropDestinations
    navigationSection: root.navigationPanelSec(dockPanelView.location)

    FretboardComponent {
        id: fretcomponent
        anchors.fill: parent
        mscore: dockPanelView.mscore
    }
}
