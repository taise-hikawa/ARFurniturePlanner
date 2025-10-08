//
//  ContentView.swift
//  ARFurniturePlanner
//
//  Created by 樋川大聖 on 2025/10/09.
//

import SwiftUI
import ARKit
import RealityKit

struct ContentView: View {
    @StateObject private var arViewManager = ARViewManager()
    
    var body: some View {
        ZStack {
            // ARViewを全画面で表示
            ARViewContainer(arViewManager: arViewManager)
                .ignoresSafeArea()
            
            // UI オーバーレイ
            VStack {
                // 上部のステータス表示
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AR家具プランナー")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        // ARセッションの状態表示
                        HStack {
                            Circle()
                                .fill(arViewManager.isSessionRunning ? .green : .red)
                                .frame(width: 8, height: 8)
                            
                            Text(arViewManager.isSessionRunning ? "AR実行中" : "AR停止中")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        
                        // トラッキング状態表示
                        Text(trackingStateText)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.6), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                Spacer()
                
                // 下部のコントロールパネル
                VStack(spacing: 16) {
                    // エラーメッセージ表示
                    if let errorMessage = arViewManager.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                    }
                    
                    // コントロールボタン
                    HStack(spacing: 20) {
                        Button(action: {
                            if arViewManager.isSessionRunning {
                                arViewManager.pauseARSession()
                            } else {
                                arViewManager.startARSession()
                            }
                        }) {
                            Image(systemName: arViewManager.isSessionRunning ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                        }
                        
                        Button(action: {
                            arViewManager.startARSession() // リセット
                        }) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear {
            // アプリが表示された時の処理
            if !arViewManager.isSessionRunning {
                arViewManager.startARSession()
            }
        }
        .onDisappear {
            // アプリが非表示になった時の処理
            arViewManager.pauseARSession()
        }
    }
    
    // トラッキング状態のテキスト表示
    private var trackingStateText: String {
        switch arViewManager.sessionState {
        case .normal:
            return "トラッキング正常"
        case .notAvailable:
            return "トラッキング利用不可"
        case .limited(.excessiveMotion):
            return "動きが激しすぎます"
        case .limited(.insufficientFeatures):
            return "特徴点が不足しています"
        case .limited(.initializing):
            return "初期化中..."
        case .limited(.relocalizing):
            return "再位置特定中..."
        default:
            return "トラッキング状態不明"
        }
    }
}

#Preview {
    ContentView()
}
