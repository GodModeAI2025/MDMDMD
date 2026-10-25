# macOS 1.0.2 (36) — review correction, 25 October2026

Apple rejected the submission under Guideline5 (mainland China availability with ChatGPT/OpenAI functionality/references) and2.4.5(i) (information requested for com.apple.security.network.server). Apple explicitly said that explaining the entitlement did not require a new binary if it is necessary.

## Applied correction

- China mainland was deselected in the app-wide storefront availability settings. Portal shows174 selected territories and China mainland moving to Not Available; propagation can take24hours. This also affects iOS, since availability is app-wide.
- network.server remains required for the existing optional ChatGPT sign-in: KI → Chat öffnen … → KI-Zugang → ChatGPT-Abo → Continue with ChatGPT. NWListener binds explicitly to127.0.0.1 on an OS-assigned temporary port and receives only the OAuth callback. It is not an MCP or public/LAN server. Callback validation, PKCE, timeout and cleanup are present.
- Reply sent to Apple with precise navigation and implementation details; Review Notes updated. The existing build36 was resubmitted and the portal now shows **Warten auf Prüfung**. Automatic publication after approval remains selected. No new binary, build number or functionality was required.

## Evidence and limits

- Source trace: Sources/SkriptumAuth/NativeSignIn.swift, OAuth.swift; Sources/SkriptumAssistant/AssistantPanel.swift; Config/SkriptumMac.entitlements. These auth/UI files are unchanged from submitted source commit a8831fe7e2dc134fc1aa7022f1993a8d172d7c5f to current source. Source matching, loopback binding, timeout/cleanup, PKCE fields and reply length were checked.
- Existing signed-build36 evidence is under ../ios35-mac36-native-open/. Current portal screenshots and exact reply/review notes are in this directory.
- No full live ChatGPT-account sign-in or unchanged functional suite was repeated. No new test/build is claimed. Apple approval/public Mac publication is still pending.
- User-supplied API keys were copied, never moved, into a private directory outside the repository. Originals remain unchanged, copies use0600 and directory0700. No private key or JWT is included in this evidence. API authentication was not needed for this portal correction and was not exercised.
