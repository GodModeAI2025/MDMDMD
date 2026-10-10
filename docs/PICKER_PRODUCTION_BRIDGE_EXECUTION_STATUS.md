# Actual production-adapter bridge execution

The owned runner archives service commit `b22f734c897710d5f0ffdbc72bd214fb81c17e04`, checks its 43-file manifest and pinned dependencies, and starts an actual HTTPS relay, signed issuer and isolated PostgreSQL schema. It runs the actual private account driver, Security-backed admission context, runtime and binding repository. Remote library seeding is fixture setup, not native library creation.

The first actual run failed. A second diagnostic run confirmed Keychain cleanup status `-34018` and a signed-out account. Neither run proves enrollment, metadata selection or durable binding. The six separate TLS contract tests pass; they do not prove the integrated chain.

The SwiftPM process lacks the required Data Protection Keychain entitlement. A suitable signed test host or the existing native simulator harness pattern is the next verification route. Do not substitute a fake credential store, change production Keychain protection or count a skipped test as execution.

Current full root regression succeeded: 58 XCTest tests and 212 executed Swift Testing tests; the additional opt-in bridge spec was skipped without fixture configuration. That is 270 executed tests, not an integrated bridge pass. The next owned host is a dedicated iOS 27 simulator app referencing the same production sources and the compile-gated verification seams. The existing admission harness and shipping app remain unchanged.

The current iOS simulator Release build succeeded. Exported-symbol inspection of the resulting universal app executable found neither `WorkspaceVerificationTLSAnchor` nor `configuredForVerification`. This supports exclusion of the verification entry points from the release configuration; it is not a signed archive, TestFlight delivery or physical-device test.

The test uses a fresh exclusive Keychain service, exact loopback control endpoint with redirects denied, private fixture configuration and owned schema/certificate/process cleanup. Test private credentials are never printed. Existing parent PostgreSQL remains available. No production hosting, Apple authorization, physical-device, PCC, updated TestFlight or full application completion is claimed.
