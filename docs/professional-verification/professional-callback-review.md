# Independent native grammar callback review

Verdict: **PASS for the callback concurrency/lifetime fix**. Reviewed current NativeWritingReviewer.swift, continuation gate and new background callback test. No source changes or Xcode/device operations performed.

The callback factory is explicitly nonisolated and returns an explicitly @Sendable closure. The closure captures only immutable Sendable QualityDocument and the lock-protected @unchecked Sendable continuation gate, rather than inheriting NativeWritingReviewer's MainActor. Foundation NSTextCheckingResult instances and grammar dictionaries are read synchronously on the SDK callback queue; no result object is transferred into an actor task. Only immutable QualityFinding values pass through the continuation. Resuming a checked continuation is valid on the background queue and resumes the suspended caller under its original actor isolation.

The mapper validates the outer range with subtraction before combining relative grammar ranges; relative bounds cannot overflow or authorize an out-of-document range. Existing QualityFinding.make performs original UTF-16/scalar/protection checks. Callback-local arrays are not shared across invocations. Duplicate, late, cancel-racing and timeout-racing callbacks are serialized by the terminal gate and cannot resume twice. Strong callback captures retain the immutable document/gate until the SDK releases its completion, which is necessary for safe late delivery; no new UI/checker retain cycle is introduced by the mapper.

The @MainActor regression test creates the callback from an actor-isolated context, constructs SDK checking results on DispatchQueue.global, calls the callback twice and verifies one offered correction. It directly exercises the inherited-actor crash mechanism instead of merely asserting source annotations. Root reports 20 module tests green; SDK build and actual textcomposer XPC callback verification remain separate root/device gates. No reproducible blocking bug identified in this change.

Export font picker displayName is a presentation-only change, without exported geometry or settings identity impact.
