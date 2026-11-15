# Local patch to OSMD 1.9.2

The bundled MIT-licensed `Resources/Web/opensheetmusicdisplay.min.js` adds 1.5 staff spaces of vertical clearance above measure numbers' collision-aware baseline. In `MusicSheetCalculator.calculateSingleMeasureNumberPlacement`, `h=Math.min(0,h)` is changed to `h=Math.min(0,h)-1.5` immediately before the label position is assigned.

This occurs before `calculateMeasureNumberSkyline` and page/system layout, so the extra space is reserved in engraving and PDF export. It does not move note durations, pitches or measure boundaries, and is not a screen-only CSS transform. The checksum in `Vendor/SHA256SUMS` records the patched bundle. Preserve the existing OSMD license notices. Reapply or replace this patch when updating OSMD.
