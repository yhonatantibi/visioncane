# 0.5.2 — readiness and door diagnostics

Depth and structure prepare independently. Ordinary detection and manual speech
remain available without spatial inference. Manual fallback explicitly says that
distance and structure are unavailable. Each model has a visible readiness state.
Failed models can be retried while the camera is stopped after preparation settles.
An in-flight native operation is not cancelled or retried concurrently.

The default object detector does not supply doors. The semantic model must load,
include an actual door category, and receive images to produce door regions.
The UI and diagnostic report now expose category availability. This is capability
information, not proof that any specific door was detected.

Door masks are grouped by connected region instead of horizontal image thirds.
A single door crossing thirds no longer creates three reports; disconnected
doors remain distinct regions. Small/noisy masks are still filtered. Semantic
errors, missing images and stale scenes still prevent verified spatial output.

Automatic spatial speech groups at most two stable features, prioritizes doors,
and repeats a feature in the same cell no sooner than 30 seconds. Manual
description remains available. This is rule-based description, not room reasoning.

Validation: Dart analysis and pure-Dart spatial regression tests run locally.
No new APK or tablet/iPhone test is claimed. Physical door recognition and range
accuracy remain unverified. Saved-photo replay is still a subsequent milestone.
Existing one-button diagnostic file export is retained and now includes model
states, supported structural categories and stream shape without image contents.
