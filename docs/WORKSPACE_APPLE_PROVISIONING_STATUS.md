# Apple identity provisioning — observed state

Read-only authenticated Developer portal inspection, 2026-10-09. Exact team SP73Z8JWXM, existing explicit App ID com.mobilebox.Skriptum.

- Access to models on Private Cloud Compute: checked/enabled in the App ID capability list.
- Sign In with Apple: unchecked/disabled in that same App ID capability list; its Configure action is disabled.
- Save was disabled. No capability, profile, key, agreement or account setting was changed during this inspection. The UI search filter selected only Sign In with Apple.

This is live portal capability evidence, not proof of physical PCC inference or an Apple identity exchange. Before native Apple login can ship, the capability and matching signed provisioning must be established, alongside the deployment's exact native audience, production origin, signing-vault reference and revocation/notification configuration. Existing internal TestFlight Build2 remains the previously verified build and is not silently replaced by later source.

The native broker source and SDK build are available; the simulator lifecycle harness and independently reviewed server/client integration remain in progress. No ready-to-use production cloud account is claimed.
