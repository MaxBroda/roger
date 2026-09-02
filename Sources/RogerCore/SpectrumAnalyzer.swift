import AVFAudio
import Accelerate
import Foundation

/// Splits audio into frequency bands: every bar stays in place and shows its own
/// range — fundamentals on the left, sibilants on the right. Instantiable because
/// the FFT plan and the smoothed previous levels outlive the call.
public final class SpectrumAnalyzer {
    /// Below is rumble, above it speech carries too little energy.
    private static let lowestFrequency: Float = 90
    private static let highestFrequency: Float = 7_000

    private static let floorDecibels: Float = -78
    private static let ceilingDecibels: Float = -24
    /// Below 1 lifts quiet bands without clipping the loud ones.
    private static let curve: Float = 0.62

    /// Levels rise fast and fall back slowly — without the afterglow the display
    /// flickers, with too much it feels sluggish.
    private static let decay: Float = 0.76
    /// Weight of the previous level on the way up. Not zero, because a headset
    /// mic rides its own automatic gain: single-frame spikes would snap the bar
    /// to full height. At 0.45 a bar still reaches nine tenths of a step within
    /// three analyses, about 60 ms — an onset still reads as immediate.
    private static let attack: Float = 0.45

    /// Analyses per second. Chunk sizes differ per device — the built-in mic
    /// delivers 10 ms, a Bluetooth headset 20 ms — and without a fixed rate the
    /// bars would rise and decay at the speed of whatever device is recording.
    private static let framesPerSecond: Double = 50

    private let fftSize: Int
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let bandBins: [Range<Int>]
    private let hopSize: Int

    private var levels: [Float]
    private var samples: [Float]
    /// The last `fftSize` samples, oldest at ``ringIndex``. A full window every
    /// time: a short chunk padded with silence would land in the rising flank of
    /// the Hann window, where the same speech reads as a whisper.
    private var ring: [Float]
    private var ringIndex = 0
    private var samplesSinceAnalysis = 0

    public var bandCount: Int { bandBins.count }

    /// - Returns: `nil` if the requested FFT size is not a power of two.
    public init?(bandCount: Int, sampleRate: Double, fftSize: Int = 1024) {
        guard bandCount > 0, fftSize > 0, fftSize & (fftSize - 1) == 0 else { return nil }
        let log2n = vDSP_Length(log2(Double(fftSize)))
        guard let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
            return nil
        }

        self.fftSize = fftSize
        self.fft = fft
        self.window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                  count: fftSize, isHalfWindow: false)
        self.bandBins = Self.bandBins(count: bandCount, sampleRate: sampleRate, fftSize: fftSize)
        self.hopSize = max(1, Int(sampleRate / Self.framesPerSecond))
        self.levels = Array(repeating: 0, count: bandCount)
        self.samples = Array(repeating: 0, count: fftSize)
        self.ring = Array(repeating: 0, count: fftSize)
    }

    /// One level between 0 and 1 per band. Every chunk feeds the window, but the
    /// levels only move once ``hopSize`` fresh samples have arrived — otherwise
    /// the previous ones come back unchanged.
    public func analyze(_ chunk: AudioChunk) -> [Float] {
        guard append(from: chunk.buffer) else { return levels }
        guard samplesSinceAnalysis >= hopSize else { return levels }
        samplesSinceAnalysis = 0
        copyWindow()

        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP.multiply(samples, window, result: &windowed)

        let magnitudes = magnitudes(of: windowed)

        for (index, bins) in bandBins.enumerated() {
            // Peak rather than mean: a strong partial should drive the bar, not be
            // diluted by silent neighbouring bins.
            let peak = bins.isEmpty ? 0 : magnitudes[bins].max() ?? 0
            let decibels = 20 * log10(max(peak, 1e-9))
            let span = Self.ceilingDecibels - Self.floorDecibels
            let normalized = min(max((decibels - Self.floorDecibels) / span, 0), 1)
            let target = pow(normalized, Self.curve)

            let inertia = target > levels[index] ? Self.attack : Self.decay
            levels[index] = levels[index] * inertia + target * (1 - inertia)
        }

        return levels
    }

    /// Appends a chunk to the ring buffer. Both sample formats, because the
    /// Speech framework names float or integer buffers as preferred depending on
    /// the model.
    private func append(from buffer: AVAudioPCMBuffer) -> Bool {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return false }

        // More than one window in a single chunk: only the tail is still audible
        // by the time it is drawn.
        let used = min(frames, fftSize)
        let offset = frames - used

        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<used {
                ring[ringIndex] = channel[offset + index]
                ringIndex = (ringIndex + 1) % fftSize
            }
        } else if let channel = buffer.int16ChannelData?[0] {
            let fullScale = Float(Int16.max)
            for index in 0..<used {
                ring[ringIndex] = Float(channel[offset + index]) / fullScale
                ringIndex = (ringIndex + 1) % fftSize
            }
        } else {
            return false
        }

        samplesSinceAnalysis += used
        return true
    }

    /// Unrolls the ring into ``samples``, oldest first.
    private func copyWindow() {
        let head = fftSize - ringIndex
        for index in 0..<head { samples[index] = ring[ringIndex + index] }
        for index in 0..<ringIndex { samples[head + index] = ring[index] }
    }

    private func magnitudes(of input: [Float]) -> [Float] {
        let half = fftSize / 2
        var realIn = input
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        var result = [Float](repeating: 0, count: half)

        realIn.withUnsafeMutableBufferPointer { realInPtr in
            imagIn.withUnsafeMutableBufferPointer { imagInPtr in
                realOut.withUnsafeMutableBufferPointer { realOutPtr in
                    imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                        let input = DSPSplitComplex(
                            realp: realInPtr.baseAddress!,
                            imagp: imagInPtr.baseAddress!
                        )
                        var output = DSPSplitComplex(
                            realp: realOutPtr.baseAddress!,
                            imagp: imagOutPtr.baseAddress!
                        )
                        fft.forward(input: input, output: &output)

                        // Only the lower half carries information — above it the
                        // spectrum of a real signal mirrors.
                        let lower = DSPSplitComplex(
                            realp: realOutPtr.baseAddress!,
                            imagp: imagOutPtr.baseAddress!
                        )
                        vDSP.absolute(lower, result: &result)
                    }
                }
            }
        }

        // Normalise so the scale stays independent of the FFT size.
        return vDSP.divide(result, Float(fftSize))
    }

    /// Logarithmic, because hearing works in octaves — linear would waste half the
    /// display on the top frequencies.
    private static func bandBins(count: Int, sampleRate: Double, fftSize: Int) -> [Range<Int>] {
        let binWidth = Float(sampleRate) / Float(fftSize)
        let highestBin = fftSize / 2
        let ratio = highestFrequency / lowestFrequency

        return (0..<count).map { index in
            let lower = lowestFrequency * pow(ratio, Float(index) / Float(count))
            let upper = lowestFrequency * pow(ratio, Float(index + 1) / Float(count))
            let lowerBin = min(max(Int(lower / binWidth), 1), highestBin - 1)
            // At least one bin per band: at the bottom the edges sit closer than
            // the resolution, and the bars would stay silent.
            let upperBin = min(max(Int(upper / binWidth), lowerBin + 1), highestBin)
            return lowerBin..<upperBin
        }
    }
}
