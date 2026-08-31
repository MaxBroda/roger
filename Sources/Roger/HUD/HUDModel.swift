import Observation
import RogerCore

/// What the HUD shows. Separate from the panel so the view only reads state and
/// knows nothing about windows.
@MainActor
@Observable
final class HUDModel {
    /// `nonisolated` because the view measures the grid off the MainActor too —
    /// these are dimensions, not state.
    nonisolated static let barCount = Design.Spectrum.bandCount

    private(set) var state: DictationState = .idle
    private(set) var bands: [Float] = Array(repeating: 0, count: HUDModel.barCount)
    private(set) var isExpanded = false

    func update(_ newState: DictationState) {
        state = newState
        if newState != .recording {
            bands = Array(repeating: 0, count: Self.barCount)
        }
    }

    func update(bands newBands: [Float]) {
        guard newBands.count == bands.count else { return }
        bands = newBands
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    /// Dictation only. Everything incidental — downloads, language changes,
    /// errors — stays in the menu bar: `.failed` looked like an open recording
    /// that never ends.
    var isVisible: Bool {
        switch state {
        case .recording, .transcribing, .injecting: true
        case .idle, .failed: false
        }
    }
}
