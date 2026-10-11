# Failed request-history admission — 2026-10-11

A reproduced write failure left an unsent prompt appended to the in-memory assistant history. A later prepared request included that prompt and persisted it on a successful retry. The regression test failed with five assertions on the original implementation, including actual retry request content and reopened disk history.

PageAssistant now builds a proposed history, writes it atomically using the existing persistence routine, and only then publishes the in-memory entries and starts the provider. A failed write keeps the existing history, consumes the failed approval and requires a newly prepared/approved retry. The test creates an actual directory at the history-file path to force write failure, checks that the provider is never called, restores the original file, then verifies retry request privacy and final reopened history.

This is controlled-provider and real local-file evidence. It does not prove live transmission, device UI, cross-window history conflict handling, asynchronous persistence, signing or current-source TestFlight delivery. The full R01–R15 product acceptance remains open. Final test/build results and SHA256 bindings are recorded in verification.json after the same running sessions reach terminal state.
