# Native credential admission checkpoint

Owner’s actual iOS 27 UIKit process passed the permanent original Security protection probe (16 assertions) and the new gated-admission probe (10 assertions), using unique synthetic scope/service/denial metadata. Production module files were compiled directly; the verification probe is excluded from production targets. This proves real simulator Security calls and local gate behavior, not Apple login, a deployed server, physical locked-state or the product account UI.

Root inspected `native.png`: both result lines are readable and do not overlap. Raw console/hierarchy remain work-only. The owned app, session, workspace and bridge were closed.

A fresh independent execution was prepared but Xcode MCP returned: “Xcode is waiting for the user to approve this request; it has been recorded.” No workspace, build or Keychain operations started on that independent attempt; its bridge is closed. Approve the recorded request using Xcode’s MCP menu bar icon (or the Xcode-provided mcp-server approval interface), then retry the independent run. This is an Xcode approval boundary, not missing task authorization. The owner’s 16+10 result remains separate evidence.
