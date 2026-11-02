# Optional AD and PADS outputs — converter 1.1 / toolbox 1.6.90

The main converter always creates the native Allegro footprint. Two independent checkboxes optionally add `AD/<symbol>.PcbLib` and `PADS/<symbol>.d` to the same result directory. Both controls start unchecked on every new form. Their state is captured before background processing and is not persisted to settings. Additional outputs are produced in the staging directory before publication; a failure prevents the entire result from being announced as complete.

## Altium

The writer emits PCB 6.0 Binary Library format inside Windows compound storage, using Windows structured-storage APIs. It writes the library header/index, required KIND=Protel_Advanced_PCB_Library and VERSION=3.00 library parameters, footprint parameters, section-name mapping, pads, tracks, solid regions, and a model-free library. Names longer than the 31-character compound-storage element limit use SectionKeys mapping. Units are 10,000 internal coordinates per mil. Pads preserve designator, copper geometry, rotation, drill/plating and explicit solder/paste expansion. Mechanical holes have no copper. Filled custom mask polygons remain regions on the corresponding mask layers.

Format research reference: OriginalCircuit/AltiumSharp, PcbLibWriter and BinaryFormatWriter, at https://github.com/issus/AltiumSharp (retrieved 2026-11-02). The standalone implementation uses its own intermediate model and Windows storage API and does not bundle that project's code or runtime.

## PADS

The writer emits a PADS V9 PCB Decals library, with metric units, label, timestamp, drawing counts, terminals and individual padstacks. The library-file header and drawing records differ from PADS board ASCII. Padstack levels -2/-1/0 mean component side / internal / opposite side. Square/rectangular copper uses RF with corner-radius/orientation/length/offset fields; oblong copper uses OF. Drill diameter/plating are specified in each padstack header. Generated layers follow standard PADS default non-copper layers. Overlong decal names are shortened to 40 characters with an eight-digit SHA256 suffix; pin names longer than 7 characters are rejected when PADS export is selected.

Primary format reference: Mentor Graphics PADS 9.4 ASCII Library File Format Specification, June 2011, https://www.freecalypso.org/pub/CAD/PADS/pdfdocs/Plib_ASCII.pdf (retrieved 2026-11-02).

## Validation on this workstation

- Four selection combinations were run through the full Allegro conversion pipeline on C25804; each produced the expected optional files and matching manifest formats.
- WinForms tests verify both new checkboxes start unchecked, including after another form instance selected them.
- Binary storage/geometry tests verify PcbLib signature, pad count, coordinates, rotation and manual mask modes.
- KiCad 7.0.6's independent Altium importer successfully enumerated and read a generated 57-pin QFN PcbLib. Additional coordinate, size and rotation comparisons use source.json and integration manifests.
- Cadence 17.4's native PADS library translator read the generated 57-pin QFN .d. Its parsing summary reported one decal, zero errors and zero warnings. The default translator mapping does not cover every non-copper layer; the generated file's PADS layer mapping is documented above.
- GUI preview was rendered and visually inspected; both new checkboxes are visible and unchecked.
- Altium Designer 17 actual-editor validation passed after a license became available: it opened the generated native PcbLib and read all 57 QFN pad designators, positions relative to the footprint origin, dimensions and rotations. All matched source data; maximum geometry rounding error was 0.000004 mm. The required version parameter is covered by a regression check.
- PADS automation COM is not registered on this workstation; PADS validation used the native Cadence PADS library parser. The optional file writers require neither AD nor PADS to be installed.

Evidence: workspace `out/lceda2allegro-options/`, including `checkboxes.png`, `integration-{none,ad,pads,both}/`, native PADS translator log under `pads-native/`, and independent readback results. AD17 readback is `ad17-fixed-readback.txt`, with comparisons in `ad17-result.txt`.
