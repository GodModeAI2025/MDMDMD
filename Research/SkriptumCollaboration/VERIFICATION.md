# Replica verification — 2026-10-09

- Official upstream tag 0.7.2 resolves to aa45d17ac92cef2b8ded63b47e65a28dc85e3418.
- Downloaded release XCFramework SHA256: 10245378e74229b026f689b039d7df3cf17aeed353706d5f420dfd164f283a86, matching the upstream manifest. SwiftPM checksum validation was retained.
- Real native macOS package test run: 9 tests, zero failures, exit 0. Cases include peer convergence, concurrent inserts, deletion/edit recovery, reorder cycles, UTF-16/CRLF and normalization byte preservation, strict malformed-tail/identity/container rejection and accepted-state rollback.
- Failed initial cases exposed upstream encoding and object-ID representation details; permanent tests remain and the implementation handles them. No mock merge engine was substituted.
- Dependency lookup was initially stalled in Keychain, proven by sampling its live process. Public fetch was retried with documented disable-keychain/disable-netrc flags; artifact verification was not disabled.
- Not yet established: iOS app linking, device behavior, durable dependency queues, authenticated backend and permission inheritance, parser memory/time limits for Internet-facing data. R08 remains open.
