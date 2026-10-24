# 0.6.0 — saved-photo review

Includes all 0.5.1 and 0.5.2 fixes. New saved-image screen supports selecting a
JPEG/PNG, repeated local analysis, Hebrew speech, user notes and JSON export.
See PHOTO-REVIEW.md for the data contract and device acceptance checks.

Dependency: Flutter's file_selector 1.1.0 (BSD-3-Clause), including its endorsed
platform packages. pubspec.lock is regenerated with these dependencies. The
Android implementation requires minSdk 24, matching this project.

Validation completed: full Dart analysis; previous 15 spatial regression checks
remain applicable. A Flutter widget test for the initial saved-image screen is
included for CI. Full Flutter tests/APK builds have not been run successfully
on this host (earlier automatic approval review blocked Flutter test/build
telemetry). Codemagic must build and run tests before device installation.

No claims of validated door recognition, calibrated range, or iOS device testing.
Saved images can reveal reproducible model mistakes; they do not establish live
camera latency, frame alignment or navigation safety.
