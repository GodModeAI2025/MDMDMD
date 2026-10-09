# Internal TestFlight build 1.0.0 (2)

Fixed release source: b913cd63ad460fa3ed60fae8b06f510bdf8a8df2, extracted into an isolated Git archive before further scheduling/Core edits. The binary includes the verified writing/export/quality and paper/window work. It does not include the later lifecycle and atomic proposal-receipt wave at 216f8f0.

Release archive and App Store export succeeded. Actual archive/exported-app signature and embedded profile readback passed bundle/team, minimum iOS 27, PCC profile/signature/runtime gate, unexpired provisioning and App Store/TestFlight eligibility checks. Export readback has testFlightInternalTestingOnly=true and version/build management disabled. The locally exported IPA checksum is in export-proof.json; this is not claimed as the checksum of Xcode's separately re-exported upload payload.

Xcode upload completed successfully. Fresh App Store Connect navigation confirmed version 1.0.0 (2), upload ID 2cda3786-25f6-45e4-a7a0-2cabfb0971dd, status **Verarbeitung läuft**. processing.jpg captures that actual portal state. Earlier browser login failure did not persist after direct navigation; the current portal is authenticated.

A subsequent fresh Build-Uploads expansion explicitly showed **Abgeschlossen** for Build 2; completion.jpg records upload completion and the remaining **Fehlende Compliance** status. Processing is complete. Build-specific export compliance, internal Mark–Intern group assignment, tester availability and physical installation remain separate unproven gates. No encryption declaration was selected/submitted and no public/external release was performed. Existing Build 1 remains visibly missing compliance at this snapshot. Full R01–R15/product acceptance remains open.
