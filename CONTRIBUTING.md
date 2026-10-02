# Contributing

Use Xcode 27 and Swift 6. Keep Health access explicit, preview data clearly labelled, and workout state owned by the main actor. Preserve zone boundaries and missing-data states. Never commit signing identities, health exports, simulator records, build output, or personal provisioning files.

Run the core tests in Debug and Release, build both app targets, and exercise the native preview workflows before submitting a change. Real recording, permission changes, interruptions, and synchronization need paired-device validation; do not represent preview checks as sensor tests.

Use focused Conventional Commits and describe the user-visible change and verification in pull requests.
