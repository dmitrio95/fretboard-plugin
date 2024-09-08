# Changelog

### 0.6.0 - 2024-09-08
- Add support for MuseScore 4.4
- Fix few issues with note input

### 0.5.0 - 2022-12-19
- Add support for MuseScore 4
- The plugin now automatically determines a number of strings and frets for the selected instrument and switches its settings accordingly. Handling of tunings for different instruments is also partially improved. (Requires MuseScore 3.5)
- Allow horizontal flip of the fretboard for left-handed players

### 0.4.0 - 2021-10-25
- Fretboard now displays all selected notes for a range selection. To avoid possible confusion note input is blocked in this case. (Requires MuseScore 3.5)

### 0.3.0 - 2020-01-30
- Note input process:
  - Add labels with note names to note markers
  - Show semi-transparent note labels on hovering a fret
- Internal changes:
  - Adapt to possible Cursor API changes (https://github.com/musescore/MuseScore/pull/5657):
    - Ensure internal Cursor is always synchronized with user input state
    - Move input cursor to the relevant string after note input

### 0.2.0 - 2019-12-08
- Note input process:
  - Make a chord be played when adding a note to it. Previously this worked only for the first note in a chord. (Requires MuseScore 3.3.4)
  - Prevent incorrect moving of cursor from the edited chord after adding a note (Requires MuseScore 3.3.4)
  - Improve switching between voices while adding notes
- Styling and visual appearance:
  - Make appearance of fretboard controls in dark mode better
  - Make combo boxes wide enough to make their full text visible in all translations

### 0.1.0 - 2019-10-07
- Initial version
