//
//  Speak_Play.swift
//  Lightin0
//
//  Created by 向鑫 on 4/24/25.
//
import AVFoundation

import AVFoundation

/// Thread-safe, low-latency player for OpenAI `response.audio.delta` frames.
final class AudioPlayer: ObservableObject {

    // MARK: -- Private Core-Audio objects
    private let engine      = AVAudioEngine()
    private let playerNode  = AVAudioPlayerNode()

    /// Assistant audio is *always* PCM-16, 1-ch, 24 kHz, little-endian
    private let oaiFormat   = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate:   24_000,
        channels:     1,
        interleaved:  true)!

    /// Hardware / system output format (e.g. 48 kHz / stereo on most iPhones)
    private let hwFormat: AVAudioFormat

    /// One long-lived converter, created once and reused for every delta
    private let converter: AVAudioConverter

    // MARK: -- Init
    init?() {
        // Ask the engine what the output-node is really running at
        hwFormat  = engine.outputNode.inputFormat(forBus: 0)

        // Build converter 24 kHz → hardware
        guard let cvt = AVAudioConverter(from: oaiFormat, to: hwFormat) else { return nil }
        converter = cvt

        // playerNode → main mixer in *hardware* format (avoids -10868)  [oai_citation:0‡Apple Developer](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions?utm_source=chatgpt.com)
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: hwFormat)

        do { try engine.start() } catch {
            assertionFailure("AudioEngine failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: -- Public API
    /// Feed one `delta` frame that you got from the websocket
    func enqueue(_ base64PCM: String) {
        guard let data = Data(base64Encoded: base64PCM) else { return }

        // ---- 1. create *input* buffer in 24 kHz format ----------------------
        let inFrames = UInt32(data.count / 2)            // Int16 ⇒ two bytes
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: oaiFormat,
                                           frameCapacity: inFrames) else { return }
        inBuf.frameLength = inFrames

        data.withUnsafeBytes { raw in                    // safe fast copy
            guard let src = raw.baseAddress else { return }
            memcpy(inBuf.int16ChannelData![0], src, data.count)
        }

        // ---- 2. create *output* buffer in hardware format -------------------
        // Ratio may differ (24 k → 48 k == 2×); ask converter for needed frames
        let ratio      = hwFormat.sampleRate / oaiFormat.sampleRate
        let outFrames  = UInt32(Double(inFrames) * ratio) + 16  // a bit of head-room
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: hwFormat,
                                            frameCapacity: outFrames) else { return }

        // ---- 3. run the converter once --------------------------------------
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return inBuf
        }

        do {
            try converter.convert(to: outBuf, error: nil, withInputFrom: inputBlock)   //  [oai_citation:1‡Apple Developer](https://developer.apple.com/news/site-updates/?id=01112023a)
        } catch {
            print("⚠️ AVAudioConverter error: \(error)")
            return
        }

        // ---- 4. enqueue to the player node ----------------------------------
        playerNode.scheduleBuffer(outBuf,
                                      completionHandler: nil)

        if !playerNode.isPlaying { playerNode.play() }
    }
    
    func stop() {
        playerNode.stop()                                            //
        playerNode.reset()                                           // clears any queued buffers
    }
}
