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
    @State private var isFurnitureSelectionExpanded = true
    
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
                        
                        // 平面検出状態表示
                        Text(planeDetectionStatusText)
                            .font(.caption2)
                            .foregroundColor(planeDetectionStatusColor)
                            .padding(.top, 2)
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
                
                // 平面検出ガイダンス（中央表示）
                if shouldShowPlaneDetectionGuidance {
                    VStack(spacing: 16) {
                        // アニメーション付きインジケーター
                        PlaneDetectionIndicator(status: arViewManager.planeDetectionStatus)
                        
                        // ガイダンスメッセージ
                        Text(planeDetectionGuidanceText)
                            .font(.body)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.black.opacity(0.7))
                                    .padding(.horizontal, -16)
                                    .padding(.vertical, -8)
                            )
                    }
                    .transition(.opacity.combined(with: .scale))
                }
                
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
                    
                    // 家具選択UI（平面検出完了時のみ表示）
                    if arViewManager.planeDetectionStatus == .found && !arViewManager.furnitureRepository.availableFurniture.isEmpty {
                        VStack(spacing: 8) {
                            // 開閉トグルボタン
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isFurnitureSelectionExpanded.toggle()
                                }
                            }) {
                                HStack {
                                    Image(systemName: isFurnitureSelectionExpanded ? "chevron.down" : "chevron.up")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(isFurnitureSelectionExpanded ? "家具選択を隠す" : "家具選択を表示")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.black.opacity(0.6))
                                )
                            }
                            
                            // 家具選択ビュー（展開時のみ表示）
                            if isFurnitureSelectionExpanded {
                                FurnitureSelectionView(arViewManager: arViewManager, isExpanded: $isFurnitureSelectionExpanded)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .bottom).combined(with: .opacity)
                                    ))
                            }
                        }
                        .padding(.bottom, 8)
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
                            arViewManager.togglePlaneVisualization()
                        }) {
                            Image(systemName: arViewManager.showPlaneVisualization ? "eye.fill" : "eye.slash.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                        
                        // 選択家具削除ボタン
                        if arViewManager.getSelectedFurnitureCount() > 0 {
                            Button(action: {
                                arViewManager.deleteSelectedFurniture()
                            }) {
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        // 全削除ボタン
                        if arViewManager.getPlacedFurnitureCount() > 0 {
                            Button(action: {
                                arViewManager.clearAllFurniture()
                            }) {
                                Image(systemName: "clear.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.orange)
                            }
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
    
    // 平面検出状態のテキスト表示
    private var planeDetectionStatusText: String {
        switch arViewManager.planeDetectionStatus {
        case .searching:
            return "平面を検索中... (\(arViewManager.detectedPlanes.count)個検出)"
        case .found:
            return "平面検出完了 (\(arViewManager.detectedPlanes.count)個)"
        case .insufficient:
            return "照明不足 - より明るい場所で試してください"
        case .failed:
            return "平面検出に失敗しました"
        }
    }
    
    // 平面検出状態の色
    private var planeDetectionStatusColor: Color {
        switch arViewManager.planeDetectionStatus {
        case .searching:
            return .yellow
        case .found:
            return .green
        case .insufficient:
            return .orange
        case .failed:
            return .red
        }
    }
    
    // 平面検出ガイダンスを表示するかどうか
    private var shouldShowPlaneDetectionGuidance: Bool {
        return arViewManager.planeDetectionStatus != .found || arViewManager.detectedPlanes.isEmpty
    }
    
    // 平面検出ガイダンステキスト
    private var planeDetectionGuidanceText: String {
        switch arViewManager.planeDetectionStatus {
        case .searching:
            return "床や机などの平らな表面にカメラを向けて、ゆっくりと動かしてください"
        case .found:
            return "平面が検出されました！タップして家具を配置できます"
        case .insufficient:
            return "照明が不足しています。より明るい場所に移動するか、ライトを点けてください"
        case .failed:
            return "平面検出に失敗しました。アプリを再起動してもう一度お試しください"
        }
    }
}

// MARK: - PlaneDetectionIndicator View
struct PlaneDetectionIndicator: View {
    let status: ARViewManager.PlaneDetectionStatus
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // 背景円
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                    .frame(width: 80, height: 80)
                
                // アニメーション円
                Circle()
                    .stroke(indicatorColor, lineWidth: 3)
                    .frame(width: 80, height: 80)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0.0 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                
                // 中央アイコン
                Image(systemName: indicatorIcon)
                    .font(.system(size: 30))
                    .foregroundColor(indicatorColor)
            }
            
            // ステータステキスト
            Text(statusText)
                .font(.headline)
                .foregroundColor(.white)
        }
        .onAppear {
            if status == .searching {
                isAnimating = true
            }
        }
        .onChange(of: status) { _, newStatus in
            isAnimating = (newStatus == .searching)
        }
    }
    
    private var indicatorColor: Color {
        switch status {
        case .searching:
            return .blue
        case .found:
            return .green
        case .insufficient:
            return .orange
        case .failed:
            return .red
        }
    }
    
    private var indicatorIcon: String {
        switch status {
        case .searching:
            return "viewfinder"
        case .found:
            return "checkmark.circle.fill"
        case .insufficient:
            return "lightbulb.slash"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var statusText: String {
        switch status {
        case .searching:
            return "平面を検索中..."
        case .found:
            return "検出完了"
        case .insufficient:
            return "照明不足"
        case .failed:
            return "検出失敗"
        }
    }
}

#Preview {
    ContentView()
}
