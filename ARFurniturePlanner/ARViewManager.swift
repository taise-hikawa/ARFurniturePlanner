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
    @Published var detectedPlanes: [UUID: ARPlaneAnchor] = [:]
    @Published var planeDetectionStatus: PlaneDetectionStatus = .searching
    @Published var showPlaneVisualization = true
    
    // MARK: - Private Properties
    private var arSession: ARSession?
    private var arView: ARView?
    private var planeEntities: [UUID: ModelEntity] = [:]
    
    // MARK: - Enums
    enum PlaneDetectionStatus: Equatable {
        case searching
        case found
        case insufficient
        case failed
    }
    
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
            Task { @MainActor in
                self.errorMessage = "ARSessionが初期化されていません"
            }
            return
        }
        
        // ARWorldTrackingConfigurationを設定
        let configuration = ARWorldTrackingConfiguration()
        
        // 水平面検出を有効化（要件1.2に基づく）
        configuration.planeDetection = [.horizontal]
        
        // 環境テクスチャリングを有効化
        configuration.environmentTexturing = .automatic
        
        // ライト推定を有効化
        configuration.isLightEstimationEnabled = true
        
        // ARKit対応チェック
        guard ARWorldTrackingConfiguration.isSupported else {
            Task { @MainActor in
                self.errorMessage = "このデバイスはARWorldTrackingをサポートしていません"
            }
            return
        }
        
        // セッション開始
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        // 状態更新を次のrun loopで実行
        Task { @MainActor in
            // 平面検出状態をリセット
            self.detectedPlanes.removeAll()
            self.planeDetectionStatus = .searching
            self.isSessionRunning = true
            self.errorMessage = nil
        }
    }
    
    /// ARSessionを停止
    func stopARSession() {
        arSession?.pause()
        Task { @MainActor in
            self.isSessionRunning = false
        }
    }
    
    /// ARSessionを一時停止
    func pauseARSession() {
        arSession?.pause()
        Task { @MainActor in
            self.isSessionRunning = false
        }
    }
    
    /// ARViewを設定
    func setARView(_ arView: ARView) {
        self.arView = arView
        self.arView?.session = arSession ?? ARSession()
    }
    
    // MARK: - Plane Detection Management
    
    /// 平面が追加された時の処理
    private func handlePlaneAdded(_ planeAnchor: ARPlaneAnchor) {
        detectedPlanes[planeAnchor.identifier] = planeAnchor
        updatePlaneDetectionStatus()
        
        // 平面の可視化エンティティを作成
        if showPlaneVisualization {
            createPlaneVisualization(for: planeAnchor)
        }
        
        print("平面が検出されました: \(planeAnchor.identifier)")
        print("平面サイズ: \(planeAnchor.planeExtent)")
    }
    
    /// 平面が更新された時の処理
    private func handlePlaneUpdated(_ planeAnchor: ARPlaneAnchor) {
        detectedPlanes[planeAnchor.identifier] = planeAnchor
        updatePlaneDetectionStatus()
        
        // 平面の可視化エンティティを更新
        if showPlaneVisualization {
            updatePlaneVisualization(for: planeAnchor)
        }
        
        print("平面が更新されました: \(planeAnchor.identifier)")
    }
    
    /// 平面が削除された時の処理
    private func handlePlaneRemoved(_ planeAnchor: ARPlaneAnchor) {
        detectedPlanes.removeValue(forKey: planeAnchor.identifier)
        updatePlaneDetectionStatus()
        
        // 平面の可視化エンティティを削除
        removePlaneVisualization(for: planeAnchor)
        
        print("平面が削除されました: \(planeAnchor.identifier)")
    }
    
    /// 平面検出状態を更新
    private func updatePlaneDetectionStatus(lightEstimate: ARLightEstimate? = nil) {
        let planeCount = detectedPlanes.count
        
        // 新しい状態を計算
        let newStatus: PlaneDetectionStatus
        
        // ライト推定による照明不足チェック
        if let lightEstimate = lightEstimate {
            let ambientIntensity = lightEstimate.ambientIntensity
            if ambientIntensity < 500 { // 照明が不足している場合
                newStatus = .insufficient
            } else if planeCount == 0 {
                newStatus = .searching
            } else {
                newStatus = .found
            }
        } else {
            // 平面数による状態判定
            if planeCount == 0 {
                newStatus = .searching
            } else {
                newStatus = .found
            }
        }
        
        // 状態が変わった場合のみ更新
        if planeDetectionStatus != newStatus {
            Task { @MainActor in
                self.planeDetectionStatus = newStatus
            }
        }
    }
    
    /// 検出された平面の情報を取得
    func getDetectedPlanes() -> [ARPlaneAnchor] {
        return Array(detectedPlanes.values)
    }
    
    /// 最大の平面を取得
    func getLargestPlane() -> ARPlaneAnchor? {
        return detectedPlanes.values.max { plane1, plane2 in
            let area1 = plane1.planeExtent.width * plane1.planeExtent.height
            let area2 = plane2.planeExtent.width * plane2.planeExtent.height
            return area1 < area2
        }
    }
    
    // MARK: - Plane Visualization
    
    /// 平面の可視化エンティティを作成
    private func createPlaneVisualization(for planeAnchor: ARPlaneAnchor) {
        guard let arView = arView else { return }
        
        // 平面メッシュを作成
        let planeMesh = MeshResource.generatePlane(
            width: planeAnchor.planeExtent.width,
            depth: planeAnchor.planeExtent.height
        )
        
        // 半透明のマテリアルを作成
        var material = SimpleMaterial()
        material.color = .init(tint: .blue.withAlphaComponent(0.3))
        material.roughness = 1.0
        
        // ModelEntityを作成
        let planeEntity = ModelEntity(mesh: planeMesh, materials: [material])
        
        // AnchorEntityを作成して平面に配置
        let anchorEntity = AnchorEntity(.anchor(identifier: planeAnchor.identifier))
        anchorEntity.addChild(planeEntity)
        
        // ARViewに追加
        arView.scene.addAnchor(anchorEntity)
        
        // エンティティを保存
        planeEntities[planeAnchor.identifier] = planeEntity
        
        print("平面可視化エンティティを作成: \(planeAnchor.identifier)")
    }
    
    /// 平面の可視化エンティティを更新
    private func updatePlaneVisualization(for planeAnchor: ARPlaneAnchor) {
        guard let planeEntity = planeEntities[planeAnchor.identifier] else {
            // エンティティが存在しない場合は新規作成
            createPlaneVisualization(for: planeAnchor)
            return
        }
        
        // 新しいメッシュを生成
        let updatedMesh = MeshResource.generatePlane(
            width: planeAnchor.planeExtent.width,
            depth: planeAnchor.planeExtent.height
        )
        
        // メッシュを更新
        planeEntity.model?.mesh = updatedMesh
        
        print("平面可視化エンティティを更新: \(planeAnchor.identifier)")
    }
    
    /// 平面の可視化エンティティを削除
    private func removePlaneVisualization(for planeAnchor: ARPlaneAnchor) {
        guard let planeEntity = planeEntities[planeAnchor.identifier] else { return }
        
        // エンティティを削除
        planeEntity.removeFromParent()
        planeEntities.removeValue(forKey: planeAnchor.identifier)
        
        print("平面可視化エンティティを削除: \(planeAnchor.identifier)")
    }
    
    /// 平面可視化の表示/非表示を切り替え
    func togglePlaneVisualization() {
        showPlaneVisualization.toggle()
        
        if showPlaneVisualization {
            // すべての検出済み平面に対して可視化を作成
            for planeAnchor in detectedPlanes.values {
                createPlaneVisualization(for: planeAnchor)
            }
        } else {
            // すべての可視化エンティティを削除
            for planeAnchor in detectedPlanes.values {
                removePlaneVisualization(for: planeAnchor)
            }
        }
    }
    
    /// 平面境界の可視化（デバッグモード用）
    private func createPlaneBoundaryVisualization(for planeAnchor: ARPlaneAnchor) {
        guard let arView = arView else { return }
        
        // 平面の境界線を作成
        let geometry = planeAnchor.geometry
        let _ = geometry.vertices
        let _ = geometry.textureCoordinates
        
        // 境界線用のマテリアル
        var boundaryMaterial = SimpleMaterial()
        boundaryMaterial.color = .init(tint: .red)
        
        // 境界線の描画は複雑なため、シンプルな枠線で代用
        let frameMesh = MeshResource.generateBox(
            width: planeAnchor.planeExtent.width + 0.01,
            height: 0.001,
            depth: planeAnchor.planeExtent.height + 0.01
        )
        
        let frameEntity = ModelEntity(mesh: frameMesh, materials: [boundaryMaterial])
        
        let anchorEntity = AnchorEntity(.anchor(identifier: planeAnchor.identifier))
        anchorEntity.addChild(frameEntity)
        
        arView.scene.addAnchor(anchorEntity)
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
            
            // ライト推定の確認
            if let lightEstimate = frame.lightEstimate {
                self.updatePlaneDetectionStatus(lightEstimate: lightEstimate)
            }
        }
    }
    
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    self.handlePlaneAdded(planeAnchor)
                }
            }
        }
    }
    
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    self.handlePlaneUpdated(planeAnchor)
                }
            }
        }
    }
    
    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    self.handlePlaneRemoved(planeAnchor)
                }
            }
        }
    }
    
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "ARSession エラー: \(error.localizedDescription)"
            self.isSessionRunning = false
            self.planeDetectionStatus = .failed
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