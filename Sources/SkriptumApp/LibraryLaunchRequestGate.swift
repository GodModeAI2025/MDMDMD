/// A scene's open request survives attachment and presentation transitions.
/// Only a confirmed presentation may consume the exact request it started.
struct LibraryLaunchRequestGate {
    static let storageKey = "Scriptum.libraryLaunchRequest"
    enum Availability { case detached, transitioning, ready, visible }
    enum Decision: Equatable { case wait, present(String), consume(String) }
    private(set) var inFlight: String?

    mutating func evaluate(request: String, availability: Availability) -> Decision {
        guard !request.isEmpty else { return .wait }
        switch availability {
        case .detached, .transitioning: return .wait
        case .visible: return .consume(request)
        case .ready:
            guard inFlight == nil else { return .wait }
            inFlight = request
            return .present(request)
        }
    }
    mutating func complete(token: String, currentRequest: String, presented: Bool) -> String {
        guard inFlight == token else { return currentRequest }
        inFlight = nil
        return presented && currentRequest == token ? "" : currentRequest
    }
}
