# Saved-image review (0.6.0)

Stop the camera, then select “בדיקה מתמונה שמורה”. Choose a local JPEG or PNG,
tap analyse, review the text and feature list, and optionally speak the result.
The same normalized image is passed to detection, depth and semantic models.
Repeat analysis without selecting the image again to compare behavior.

First model downloads require connectivity. Inference stays on-device. A cloud
file provider selected in the system picker may itself download a selected file;
choose a locally available image for an offline test.

Input files are limited to 15 MiB and 40 million decoded pixels; model input is
resized to a maximum edge of 1280. Review the displayed orientation before
interpreting positions. The app keeps the normalized image in memory and does
not deliberately persist or include it in exported reports. The OS picker may
maintain its own temporary cache.

All descriptions explicitly refer to a saved image. They never enter the live
scene or live announcement scheduler. Depth is an uncalibrated model estimate
for the photographed scene, not the user's current distance from a screen.
Processing time excludes downloads/model loading, includes all three inference
stages, and is not live camera FPS. CPU is requested for this repeatable mode;
actual hardware execution is not verified.

Add notes describing a missed door or incorrect description and share the JSON
report. The report contains results, model states, time, errors and user notes;
it contains neither image bytes nor source filename/path.

Device acceptance still needed: picker cancellation, landscape/portrait photos,
large/invalid images, repeated analysis, back during inference, stop speech,
offline restart after downloads, and door-positive/door-negative images.
This feature does not claim validated door recognition or range accuracy.
