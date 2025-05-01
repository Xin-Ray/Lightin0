//
//  voice.swift
//  Lightin0
//
//  Created by 向鑫 on 4/23/25.
//

//
//  voice.swift
//  LightIn
//
//  Created by 向鑫 on 4/23/25.
//

import AVFoundation

class AudioCaptureManager: ObservableObject {
    private var audioEngine = AVAudioEngine() //私有变量
    private var inputNode: AVAudioInputNode!
    private var audioFormat: AVAudioFormat!
    private var isCapturing = false
    private var converter: AVAudioConverter?
    // ① 顶部：专门给 Tap 用的串行队列
    private let micQueue = DispatchQueue(label: "mic.process")

    var socketManager: AudioWebSocketManager?
    
    init(socketManager: AudioWebSocketManager) {
        self.socketManager = socketManager
    }
    
    //需要初始化并启动 AVAudioEngine 的实例。 接下来，配置 AVAudioSession ，将其类别设置为 .playAndRecord，设置所需的音频格式，例如采样率、通道数和位深度，然后激活会话。务必请求麦克风权限 。AVAudioSession 的正确设置确保了应用程序拥有必要的权限，并为录制正确配置了音频硬件。
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // 设置类别为播放和录音（同时支持录音和播放）
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            
            //（可选）让回声对齐更快，10 ms 缓冲
//            try session.setPreferredIOBufferDuration(0.01)
            
            // 设置采样率、通道数（例如单声道，16kHz）
//            try session.setPreferredSampleRate(24000)
            try session.setPreferredInputNumberOfChannels(1)
            
            // 激活音频会话
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            // 请求麦克风权限
            AVAudioApplication.requestRecordPermission { granted in
                if granted {
                    print("Microphone permission granted.")
                } else {
                    print("Microphone permission denied.")
                }
            }
            
            
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    //之后，需要访问引擎的输入节点 (audioEngine.inputNode) 及其输出格式。通过在输入节点的总线上安装一个 tap，可以接收包含捕获的音频数据的 AVAudioPCMBuffer 对象。安装在输入节点上的 tap 允许开发者拦截来自麦克风的原始音频数据流，这些数据以缓冲区对象的形式提供。
//    private func setupAudioEngine() {
//        inputNode = audioEngine.inputNode
//        
//        // 系统实际输入格式（通常是 44.1kHz 或 48kHz）
//        let inputFormat = inputNode.inputFormat(forBus: 0)
//        
//        // 目标格式（你想要的格式：16kHz / 单声道 / Float32）
////        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
//        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
//                                               sampleRate: 24_000,
//                                               channels: 1,
//                                               interleaved: true) else {
//            print("❌ 无法创建目标音频格式")
//            return
//        }
//
//        // 转换器
//        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
//
//        inputNode.removeTap(onBus: 0)
//        inputNode.installTap(onBus: 0,
//                             bufferSize: 960,
//                             format: inputFormat) { [weak self] buffer, time in
//            guard let self = self, let converter = self.converter else { return }
//
//            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
//                                                         frameCapacity: 960 * 2) else {
//                return
//            }
//
//            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
//                outStatus.pointee = .haveData
//                return buffer
//            }
//
//            var error: NSError? = nil
//            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
//
//            if let error = error {
//                print("❌ 转换失败: \(error)")
//                return
//            }
//
//            // 直接拿 Int16 PCM 数据
//            if let int16Data = convertedBuffer.int16ChannelData {
//                let frameLength = Int(convertedBuffer.frameLength)
//                let data = Data(bytes: int16Data.pointee, count: frameLength * 2)
//
//                // 🔥 直接通过 WebSocket 发送
//                self.socketManager?.sendAudioData(data)
//            }
//        }
//
//        audioEngine.prepare()
//
//        do {
//            try audioEngine.start()
//            print("🎤 音频采集已启动（并转换为 16kHz）")
//        } catch {
//            print("❌ 无法启动音频引擎: \(error)")
//        }
//    }


    // ……………………………………………………………………………………………………………………
    private func setupAudioEngine() {

        inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)          // 48 kHz / 1-ch / F32

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: 24_000,
                                               channels: 1,
                                               interleaved: true) else { return }

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0,
                             bufferSize: 960,                        // 20 ms @ 48 kHz
                             format: inputFormat) { [weak self] buf, _ in
            guard let self else { return }

            // 🚚 **别在实时线程里干重活**——丢到后台串行队列
            self.micQueue.async { [weak self] in
                guard let self,
                      let cvt = self.converter,
                      let out = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                 frameCapacity: 960) else { return }

                var err: NSError?
                cvt.convert(to: out, error: &err) { _, st in
                    st.pointee = .haveData
                    return buf
                }
                if err != nil { print("❌ 转换失败: \(err!)"); return }

                // 快速 copy → Data → 走主线程外的网络线程
                if let src = out.int16ChannelData?.pointee {
                    let n = Int(out.frameLength)
                    let pcm = Data(bytes: src, count: n * 2)
                    self.socketManager?.sendAudioData(pcm)         // sendAudioData 已经自己做 Base-64
                }
            }
        }

        try? audioEngine.start()
        print("🎤 Mic 48 kHz → AEC → 24 kHz 已启动")
    }
    
    
    
    
    //由于 WebSocket 主要处理文本或二进制帧，因此需要将捕获到的二进制音频数据编码为 Base64 格式  以便通过 WebSocket 传输。首先，从 AVAudioPCMBuffer 中提取原始音频数据（例如，使用 pcmBuffer.floatChannelData 或 pcmBuffer.int16ChannelData）。然后，将原始音频数据转换为 Data 对象。最后，使用 Data 对象的 base64EncodedString(options:) 方法  将二进制数据编码为 Base64 字符串。Swift 的 Data 类提供了内置的 Base64 编码功能，使得这个过程非常简单。 在音频缓冲区 tap 中，Base64 编码过程通常在获取到音频数据后立即进行。
//    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
//        guard let channelData = buffer.floatChannelData else {
//            print("No audio data available")
//            return
//        }
//
//        // 获取音频数据的帧数
//        let frameLength = Int(buffer.frameLength)
//        let channels = Int(buffer.format.channelCount)
//
//        // 以 float 形式获取音频样本数据
//        let audioSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength * channels))
//
//        // 转换为 Data 对象（二进制数据）
//        let data = audioSamples.withUnsafeBufferPointer { Data(buffer: $0) }
//
//        //发送websocket
//        socketManager?.sendAudioData(data)
//    }
    
    private func convertBufferToData(buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> Data? {
        guard let floatChannelData = buffer.floatChannelData?[0] else { return nil }
        let frameLength = Int(buffer.frameLength)

        var int16Data = [Int16](repeating: 0, count: frameLength)
        for i in 0..<frameLength {
            let sample = floatChannelData[i]
            int16Data[i] = Int16(sample * Float(Int16.max))
        }

        let data = int16Data.withUnsafeBytes { Data($0) }

        return data
    }
    
    func startAudioCapture() {
        guard !isCapturing else {
            print("🔁 Already capturing audio.")
            return
        }

        setupAudioSession()
        setupAudioEngine()
        isCapturing = true
        print("✅ Audio capture started.")
    }
    
    
    func stopAudioCapture() {
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Failed to deactivate AVAudioSession: \(error)")
        }

        print("🛑 Audio capture stopped.")
    }

    
    
}





