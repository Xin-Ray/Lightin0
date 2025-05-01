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
    var socketManager: AudioWebSocketManager?
    
    init(socketManager: AudioWebSocketManager) {
        self.socketManager = socketManager
        setupAudioSession()
        setupAudioEngine()
    }
    
    //需要初始化并启动 AVAudioEngine 的实例。 接下来，配置 AVAudioSession ，将其类别设置为 .playAndRecord，设置所需的音频格式，例如采样率、通道数和位深度，然后激活会话。务必请求麦克风权限 。AVAudioSession 的正确设置确保了应用程序拥有必要的权限，并为录制正确配置了音频硬件。
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // 设置类别为播放和录音（同时支持录音和播放）
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            
            // 设置采样率、通道数（例如单声道，16kHz）
            try session.setPreferredSampleRate(16000)
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
    private func setupAudioEngine() {
        inputNode = audioEngine.inputNode
        audioFormat = inputNode.outputFormat(forBus: 0) // 获取默认格式（或自定义格式）
        
        // 安装 tap 以获取实时音频缓冲区
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { buffer, when in
            self.processAudioBuffer(buffer: buffer)
        }
        
        // 启动 AVAudioEngine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("AudioEngine failed to start: \(error)")
        }
    }
    
    //由于 WebSocket 主要处理文本或二进制帧，因此需要将捕获到的二进制音频数据编码为 Base64 格式  以便通过 WebSocket 传输。首先，从 AVAudioPCMBuffer 中提取原始音频数据（例如，使用 pcmBuffer.floatChannelData 或 pcmBuffer.int16ChannelData）。然后，将原始音频数据转换为 Data 对象。最后，使用 Data 对象的 base64EncodedString(options:) 方法  将二进制数据编码为 Base64 字符串。Swift 的 Data 类提供了内置的 Base64 编码功能，使得这个过程非常简单。 在音频缓冲区 tap 中，Base64 编码过程通常在获取到音频数据后立即进行。
    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            print("No audio data available")
            return
        }

        // 获取音频数据的帧数
        let frameLength = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)

        // 以 float 形式获取音频样本数据
        let audioSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength * channels))

        // 转换为 Data 对象（二进制数据）
        let data = audioSamples.withUnsafeBufferPointer { Data(buffer: $0) }

        //发送websocket
        socketManager?.sendAudioData(data)
    }
    
    func stopAudioCapture() {
        inputNode.removeTap(onBus: 0)  // 移除音频tap
        audioEngine.stop()             // 停止引擎
    }

    
    
}





