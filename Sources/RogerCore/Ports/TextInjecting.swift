/// Puts the text into the app that currently has focus.
public protocol TextInjecting: Sendable {
    func inject(_ transcript: Transcript) async throws
}
