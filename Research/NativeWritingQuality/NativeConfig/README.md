# Pinned reachability metadata

These six JSON files are retained verbatim from the Graal Java 17 native-image agent. The original multilingual metadata was merged with a fresh, network-denied run of all 29 parity witnesses extended by blank lines and 19 spaces, matching masked inline Markdown. See `docs/qa-native-worker-20261015` for the input, successful JVM trace, build commands and native integration regression.

The extended Chinese witness reaches HanLP's character-type/segmentation data, a path missed by the original short sentence. The source resource configuration separately includes the unchanged `data/` files from the pinned HanLP JAR. These remain embedded native resources; they are not entries in the external LanguageTool rule pack.

The POM uses this directory by default. Supply `-Dscriptum.agentDirectory=<fresh metadata>` when regenerating. Keep regenerated metadata and its evidence together; metadata presence does not prove comprehensive language quality or authorize distribution.
