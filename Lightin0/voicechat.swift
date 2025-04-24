//
//  voicechat.swift
//  Lightin0
//
//  Created by 向鑫 on 4/23/25.
//

//
//  voicechat0.swift
//  LightIn
//
//  Created by 向鑫 on 4/23/25.
//
import SwiftUI

struct voiceContentView: View {
    @StateObject private var socketManager = AudioWebSocketManager()
    @StateObject private var audioManager: AudioCaptureManager

    init() {
        let ws = AudioWebSocketManager()
        _socketManager = StateObject(wrappedValue: ws)
        _audioManager = StateObject(wrappedValue: AudioCaptureManager(socketManager: ws))
    }

    var body: some View {
        VStack {
            Button("Connect WebSocket") {
                socketManager.connect()
            }

            Button("Start Audio") {
                // 音频开始后自动发送
            }

            Button("Stop Audio") {
                audioManager.stopAudioCapture()
            }

            Button("Disconnect WebSocket") {
                socketManager.disconnect()
            }
        }
    }
}
