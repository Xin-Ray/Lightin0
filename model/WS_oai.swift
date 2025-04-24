
//
//  WS_oai_api.swift
//  LightIn
//
//  Created by 向鑫 on 4/11/25.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

class AudioWebSocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate{
    /// 回调：当接收到服务器消息后调用
    var onMessageReceived: ((String) -> Void)?
    
    /// 回调：连接成功
    var onConnected: (() -> Void)?
    
    /// 回调：连接断开
    var onDisconnected: (() -> Void)?
    
    /// 回调：连接出错
    var onError: ((Error) -> Void)?
    
    private var webSocketTask: URLSessionWebSocketTask?
    
    func connect() {
        guard let url = URL(string: "wss://flykid.xyz/ws/lightin_app/") else { return }
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }
    
    func sendAudioData(_ data: Data) {
        let base64String = data.base64EncodedString()
        
        // 可选：封装成 JSON 格式以便后端解析
        let messageDict = ["type": "audio_chunk", "data": base64String]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: messageDict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            send(text: jsonString)
        }
    }
    
    func send(text: String) {
        let message = URLSessionWebSocketTask.Message.string(text)
        webSocketTask?.send(message) { error in
            if let error = error {
                print("WebSocket Send Error: \(error)")
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("WebSocket Receive Error: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    print("WebSocket Received String: \(text)")
                case .data(let data):
                    print("WebSocket Received Data: \(data)")
                @unknown default:
                    print("WebSocket Received Unknown Format")
                }
                self?.receiveMessage() // 继续监听
            }
        }
    }
//    /// 持续接收消息（轮询式的异步调用）
//    private func receiveMessage() {
//        webSocketTask?.receive { [weak self] result in
//            switch result {
//            case .failure(let error):
//                print("接收消息出错：\(error)")
//            case .success(let message):
//                switch message {
//                case .data(let data):
//                    if let response = String(data: data, encoding: .utf8) {
//                        self?.onMessageReceived?(response)
//                    }
//                case .string(let text):
//                    self?.onMessageReceived?(text)
//                @unknown default:
//                    break
//                }
//            }
//            // 递归调用以持续接收消息
//            self?.receiveMessage()
//        }
//    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        onDisconnected?()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        print("WebSocket did connect")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        print("WebSocket did disconnect with code: \(closeCode)")
    }
}




class AudioMonitor: ObservableObject {
    private var audioEngine = AVAudioEngine()
    
    /// 当采集到音频数据时的回调（Data 格式，采样数据转换为 Int16）
    var onAudioFrameCaptured: ((Data) -> Void)?
    
    /// 启动音频采集
    func startMonitoring() {
        let inputNode = audioEngine.inputNode
        let bus = 0
        // 获取输入格式（通常为 LPCM 格式）
        let inputFormat = inputNode.inputFormat(forBus: bus)
        
        // 在输入节点上添加 tap 回调，每次采集一定数量的音频数据（bufferSize: 1024 可根据实际情况调整）
        inputNode.installTap(onBus: bus, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            // 把采集到的音频 buffer 转换为 Data 格式，假设转换为 Int16 类型数据
            if let audioData = self.audioBufferToData(buffer: buffer, format: inputFormat) {
                // 通过回调传出数据
                DispatchQueue.main.async {
                    self.onAudioFrameCaptured?(audioData)
                }
            }
        }
        
        do {
            try audioEngine.start()
        } catch {
            print("AudioEngine 启动失败：\(error)")
        }
    }
    
    /// 停止音频采集
    func stopMonitoring() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }
    
    /// 将 AVAudioPCMBuffer 转换为 Data 格式
    /// 这里假设你希望得到 16 位整数格式（PCM）
    private func audioBufferToData(buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> Data? {
        guard let channelData = buffer.int16ChannelData?[0] else {
            // 如果你的 buffer 没有 int16ChannelData，可以考虑先从 floatChannelData 转换
            guard let floatChannelData = buffer.floatChannelData?[0] else { return nil }
            let frameLength = Int(buffer.frameLength)
            var int16Data = [Int16](repeating: 0, count: frameLength)
            for i in 0..<frameLength {
                let sample = floatChannelData[i]
                // 将 Float [-1,1] 转换为 Int16
                int16Data[i] = Int16(sample * Float(Int16.max))
            }
            return Data(buffer: UnsafeBufferPointer(start: &int16Data, count: int16Data.count))
        }
        
        // 注意：buffer.int16ChannelData 返回的是 UnsafeMutablePointer<UnsafeMutablePointer<Int16>?>，
        // 这里假设仅使用第一个声道，直接用其数据
        let frameLength = Int(buffer.frameLength)
        let bufferPointer = UnsafeBufferPointer(start: channelData, count: frameLength)
        return Data(buffer: bufferPointer)
    }
}



//class AudioChatViewModel: ObservableObject {
//    @Published var connectionStatus: String = "Disconnected"
//    @Published var receivedDelta: String = ""
//
//    private var socketManager = AudioWebSocketManager()
//    private var audioMonitor = AudioMonitor()
//
//    init() {
//        socketManager.onConnected = { [weak self] in
//            DispatchQueue.main.async {
//                self?.connectionStatus = "Connected"
//            }
//        }
//
//        socketManager.onDisconnected = { [weak self] in
//            DispatchQueue.main.async {
//                self?.connectionStatus = "Disconnected"
//            }
//        }
//
//        socketManager.onError = { [weak self] error in
//            DispatchQueue.main.async {
//                self?.connectionStatus = "Error: \(error.localizedDescription)"
//            }
//        }
//
//        socketManager.onMessageReceived = { [weak self] message in
//            DispatchQueue.main.async {
//                self?.receivedDelta = message
//            }
//        }
//
//        // 使用 AVFoundation 实时采集音频数据
//        audioMonitor.onAudioFrameCaptured = { (audioData: Data) in
//            let base64Audio = audioData.base64EncodedString()
//            self.socketManager.sendAudioData(base64Audio: base64Audio)
//        }
//    }
//
//    func connect() {
//        socketManager.connect()
//        connectionStatus = "Connected"
//        audioMonitor.startMonitoring()
//    }
//
//    func disconnect() {
//        audioMonitor.stopMonitoring()
//        socketManager.disconnect()
//        connectionStatus = "Disconnected"
//    }
//}
