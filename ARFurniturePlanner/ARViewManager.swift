//
//  ARViewManager.swift
//  ARFurniturePlanner
//
//  Created by 樋川大聖 on 2025/10/09.
//

import Foundation
import ARKit
import RealityKit
import SwiftUI

/// ARセッションとARViewを管理するクラス
@MainActor
class ARViewManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isSessionRunning = false
    @Published var sessionState: ARCamera.TrackingState = .notAvailable
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var arSession: ARSession?
    private var arView: ARView?
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupARSession()
    }
    
    // MARK: - AR Session Management
    
    /// ARSessionの初期化
    private func setupARSession() {
        arSession = ARSession()
        arSession?.delegate = self
    }
    
    /// ARSessionを開始
    func startARSession() {
        guard let arSession = arSession else {
            errorMessage = "ARSessionが初期化されていません"
            return
        }
        
        // ARWorldTrackingConfigurationを設定
        let configuration = ARWorldTrackingConfiguration()
        
        // 平面検出を有効化
        configuration.planeDetection = [.horizontal, .vertical]
        
        // ARKit対応チェック
        guard ARWorldTrackingConfiguration.isSupported else {
            errorMessage = "このデバイスはARWorldTrackingをサポートしていません"
            return
        }
        
        // セッション開始
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
        errorMessage = nil
    }
    
    /// ARSessionを停止
    func stopARSession() {
        arSession?.pause()
        isSessionRunning = false
    }
    
    /// ARSessionを一時停止
    func pauseARSession() {
        arSession?.pause()
        isSessionRunning = false
    }
    
    /// ARViewを設定
    func setARView(_ arView: ARView) {
        self.arView = arView
        self.arView?.session = arSession ?? ARSession()
    }
    
    // MARK: - Cleanup
    deinit {
        arSession?.pause()
    }
}

// MARK: - ARSessionDelegate
extension ARViewManager: ARSessionDelegate {
    
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // フレーム更新時の処理
        Task { @MainActor in
            self.sessionState = frame.camera.trackingState
        }
    }
    
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "ARSession エラー: \(error.localizedDescription)"
            self.isSessionRunning = false
        }
    }
    
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.isSessionRunning = false
        }
    }
    
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            // セッション再開
            self.startARSession()
        }
    }
}