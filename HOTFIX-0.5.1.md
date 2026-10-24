# 0.5.1 camera stream hotfix

The installed ultralytics_yolo 0.6.16 YOLOView calls onStreamingData instead
of onResult/onPerformanceMetrics when a streaming callback is supplied.
VisionCane now dispatches detections and metrics from each stream event before
spatial preparation, throttling or JPEG validation. This fixes the app remaining
in its loading state despite receiving detections, including basic detection mode.

Streaming configuration is explicitly reapplied after model load. Missing image
and missing detection-list errors are distinguished. Diagnostics include event
keys, image type/byte count and detection-list type, without storing image bytes.
Fusion still requires the image and detections from the same event.

Validation: full Dart analysis passed. Native APK and device behavior have not
been verified for this hotfix. Missing originalImage root cause on the tablet
is not yet confirmed; the explicit configuration and diagnostics address that
remaining investigation. Do not claim distance accuracy from this patch.

Device checks: start with integrated mode off, confirm loading disappears and
object descriptions work; stop camera, enable integrated mode, restart; if image
error remains, share diagnostics using the app's report export. Repeat stop/start
and verify no previous-frame distance is announced.
