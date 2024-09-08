import MuseScore.UiComponents 1.0 as MU

MU.CheckBox {
    onClicked: {
        // MuseScore checkbox doesn't switch that automatically.
        checked = !checked;
    }
}
