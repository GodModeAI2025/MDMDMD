import ScriptumGrammar

/// Compile/link witness for the packaged C module on each Apple target.
/// The host runner executes it; the iOS artifact is not execution evidence.
public func scriptumGrammarFrameworkImportProbe() -> Int32 {
    var thread: OpaquePointer?
    let created = graal_create_isolate(nil, nil, &thread)
    guard created == 0, let thread else { return created == 0 ? -100 : created }
    let configured = scriptum_quality_set_heap_limit(thread, 256 * 1024 * 1024)
    let destroyed = graal_tear_down_isolate(thread)
    return configured == 0 ? destroyed : configured
}
