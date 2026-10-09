# TestFlight feedback: simpler writing actions

Implemented direct Lektorat, Überarbeiten and Zusammenfassen buttons. Each action opens a task-specific dialog without a prompt editor, revision-mode switch or extra context chooser. Task requests exclude prior chat history by default. Completed proofreading/rewrite proposals expose direct Übernehmen/Verwerfen; summaries can be saved. Original text is retained until explicit application.

Textprüfung now has a simple start action, categorized findings and individual correction dialogs with replacement/ignore actions. Language and optional custom-server configuration moved behind Prüfeinstellungen. Initial language is detected from the document rather than chosen solely from device locale.

First simulator QA found a first-open state race and toolbar overflow. Both were corrected: typed sheet items carry the action and a responsive action strip prevents the third action from entering overflow.

Fresh Xcode-MCP verification on a 402×874-point Simulator passed: all three actions visible; FIRST Lektorat opening correct with Starten and no chat controls; summary correct; main text-check screen free of server settings; settings behind gear; German detected for German welcome text; local finding dialog opened. No AI request, credential change or document edit was performed. Device session ended.

GUI-tested source aggregate SHA-256: `99255543bde7b1d0fb6d7625a85996dd5fa267b7e1d58b6f6cd2b73b7e136d13`. Afterwards only language-display localization was corrected to German; the final iOS SDK build succeeded. AI response generation/application and physical-device behavior remain unverified. This is not a new TestFlight upload.

Evidence: [buttons](actions.png), [Lektorat](lektorat.png), [text check](text-check.png), [individual correction](correction.png).
