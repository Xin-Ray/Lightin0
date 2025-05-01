
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
    var onConnected: (() -> Void)?/// 回调：连接成功
    var onDisconnected: (() -> Void)? /// 回调：连接断开
    var onError: ((Error) -> Void)?/// 回调：连接出错
    private var pcmAccumulator = Data()
    @Published var isAssistantMuted: Bool = false

    private let audioPlayer = AudioPlayer()
    
    private var webSocketTask: URLSessionWebSocketTask?
    
    func connect() {
        guard let url = URL(string: "wss://flykid.xyz/ws/lightin_app/") else { return }
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }
    
    func sendAudioData(_ pcmPiece: Data) {
        pcmAccumulator.append(pcmPiece)

//         聚到 >= 100 ms（3 200B）再发送
        if pcmAccumulator.count >= 4800 {
            let b64 = pcmPiece.base64EncodedString()
            send(text: #"{"type":"input_audio_buffer.append","audio":"\#(b64)"}"#)
//            send(text: #"{"type":"input_audio_buffer.commit"}"#)//因为后端使用的是VAD模式。
            pcmAccumulator.removeAll(keepingCapacity: true)
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
    
//    private func receiveMessage() {
//        webSocketTask?.receive { [weak self] result in
//            // Always call receiveMessage again:
//            defer { self?.receiveMessage() }
//
//            guard
//                case .success(let msg) = result,
//                case .string(let text) = msg,
//                let raw  = text.data(using: .utf8),
//                let json = try? JSONSerialization.jsonObject(with: raw) as? [String:Any],
//                json["type"] as? String == "response.audio.delta",
//                let b64  = json["delta"] as? String
//            else { return }
//
//            DispatchQueue.main.async {
//                self?.audioPlayer?.enqueue(b64)
//            }
//        }
//    }
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            defer { self?.receiveMessage() }
            guard case .success(let msg) = result else { return }

            switch msg {
            case .string(let txt):
                guard let data = txt.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
                      let type = json["type"] as? String else { return }

                switch type {

                case "response.audio.delta":
                    guard self?.isAssistantMuted == false,   // 正在播才收
                          let b64 = json["delta"] as? String else { return }
                    self?.audioPlayer?.enqueue(b64)

//                case "server.vad_started":
//                    DispatchQueue.main.async { [weak self] in
//                        self?.isAssistantMuted = true   // ① 更新 @Published
//                        self?.audioPlayer?.stop()       // ② 操作 AVAudio
//                    }

                case "server.vad_stopped":
                    DispatchQueue.main.async { [weak self] in
                        self?.isAssistantMuted = false
                        // 如果需要 resume／unmute，可在这里调用 play()
                    }

                default: break
                }

            default: break
            }
        }
    }
    

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



