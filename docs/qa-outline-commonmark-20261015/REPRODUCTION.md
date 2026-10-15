# Reproduction

From the repository root, with the installed Apple Swift toolchain:

```sh
xcrun swift test --disable-sandbox --no-parallel --filter 'PageOutlineTests|PageLinksTests|PageNavigationTests'
```

If the default compiler cache is restricted, point both CLANG_MODULE_CACHE_PATH and SWIFT_MODULECACHE_PATH at the same writable local directory. The exact successful command environment and process exit code are retained in GREEN_COMMAND.json. No test contacts CloudKit or starts an app/device.

The RED files preserve the unchanged scanner extracted from both inspectors and the exact failing test definitions; do not overwrite the working implementation to reproduce it. Use a separate checkout and substitute only those saved projection/test files. Baseline PageLinks and PageNavigation are recoverable from main 31507fd.
