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
    private var placedFurnitureEntities: [PlacedFurnitureEntity] = []
    
    // MARK: - Furniture Management Properties
    @Published var selectedFurnitureModel: FurnitureModel?
    @Published var furnitureRepository = FurnitureRepository()
    
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
        
        // タップジェスチャーを設定
        setupTapGesture()
    }
    
    // MARK: - Gesture Setup
    
    /// タップジェスチャーを設定
    private func setupTapGesture() {
        guard let arView = arView else { return }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        print("タップジェスチャーを設定しました")
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
        
        // ログを減らすため、詳細ログは削除
        // print("平面が更新されました: \(planeAnchor.identifier)")
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
        
        // ログを減らすため、詳細ログは削除
        // print("平面可視化エンティティを更新: \(planeAnchor.identifier)")
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
    
    // MARK: - Tap Gesture Handling
    
    /// タップジェスチャーを処理
    /// - Parameter gesture: タップジェスチャー
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let arView = arView else { 
            print("ARViewが利用できません")
            return 
        }
        
        let tapLocation = gesture.location(in: arView)
        print("🔥 タップ検出: \(tapLocation)")
        
        // 既存の家具エンティティをタップしたかチェック
        if let tappedEntity = getTappedFurnitureEntity(at: tapLocation) {
            handleFurnitureEntityTap(tappedEntity)
            return
        }
        
        // 平面上への家具配置を試行
        if let selectedModel = selectedFurnitureModel {
            print("🔥 選択された家具: \(selectedModel.name)")
            attemptFurniturePlacement(at: tapLocation, model: selectedModel)
        } else {
            print("🔥 配置する家具が選択されていません")
        }
    }
    
    /// タップされた家具エンティティを取得
    /// - Parameter location: タップ位置
    /// - Returns: タップされた家具エンティティ、存在しない場合はnil
    private func getTappedFurnitureEntity(at location: CGPoint) -> PlacedFurnitureEntity? {
        guard let arView = arView else { return nil }
        
        // レイキャストを実行してエンティティを検索
        let results = arView.hitTest(location)
        
        for result in results {
            // 家具エンティティまたはその子エンティティかチェック
            var currentEntity: Entity? = result.entity
            
            while currentEntity != nil {
                if let furnitureEntity = currentEntity as? PlacedFurnitureEntity {
                    return furnitureEntity
                }
                currentEntity = currentEntity?.parent
            }
        }
        
        return nil
    }
    
    /// 家具エンティティのタップを処理
    /// - Parameter entity: タップされた家具エンティティ
    private func handleFurnitureEntityTap(_ entity: PlacedFurnitureEntity) {
        // 他の家具の選択を解除
        for furnitureEntity in placedFurnitureEntities {
            if furnitureEntity != entity {
                furnitureEntity.deselect()
            }
        }
        
        // タップされた家具の選択状態を切り替え
        entity.toggleSelection()
        
        print("家具エンティティをタップ: \(entity.furnitureModel.name) (選択: \(entity.isSelected))")
    }
    
    // MARK: - Furniture Placement
    
    /// 指定位置への家具配置を試行
    /// - Parameters:
    ///   - location: タップ位置
    ///   - model: 配置する家具モデル
    private func attemptFurniturePlacement(at location: CGPoint, model: FurnitureModel) {
        guard let arView = arView else { 
            print("ARViewが利用できません")
            return 
        }
        
        print("🔥 家具配置を試行: \(model.name) at \(location)")
        
        // レイキャストクエリを作成（水平面のみ）
        let query = arView.makeRaycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal)
        
        guard let query = query else {
            print("レイキャストクエリの作成に失敗")
            // フォールバック: 推定平面を使用
            let fallbackQuery = arView.makeRaycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal)
            if let fallbackQuery = fallbackQuery {
                let fallbackResults = arView.session.raycast(fallbackQuery)
                if let fallbackResult = fallbackResults.first {
                    let transform = fallbackResult.worldTransform
                    let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                    print("フォールバック配置位置: \(position)")
                    Task {
                        await placeFurniture(model: model, at: position)
                    }
                    return
                }
            }
            print("フォールバックも失敗")
            return
        }
        
        // レイキャストを実行
        let results = arView.session.raycast(query)
        print("🔥 レイキャスト結果数: \(results.count)")
        
        guard let firstResult = results.first else {
            print("🔥 平面が見つかりません。平面検出を確認してください。")
            print("🔥 検出済み平面数: \(detectedPlanes.count)")
            
            // フォールバック: 推定平面を使用
            let fallbackQuery = arView.makeRaycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal)
            if let fallbackQuery = fallbackQuery {
                let fallbackResults = arView.session.raycast(fallbackQuery)
                if let fallbackResult = fallbackResults.first {
                    let transform = fallbackResult.worldTransform
                    let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                    print("フォールバック配置位置: \(position)")
                    Task {
                        await placeFurniture(model: model, at: position)
                    }
                    return
                }
            }
            return
        }
        
        // ワールド座標での配置位置を計算
        let transform = firstResult.worldTransform
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        print("🔥 配置位置: \(position)")
        
        // 家具モデルを配置
        Task {
            await placeFurniture(model: model, at: position)
        }
    }
    
    /// 家具を指定位置に配置
    /// - Parameters:
    ///   - model: 配置する家具モデル
    ///   - position: 配置位置
    private func placeFurniture(model: FurnitureModel, at position: SIMD3<Float>) async {
        print("🔥 家具配置を開始: \(model.name) at \(position)")
        
        // 家具モデルを読み込み
        guard let modelEntity = await furnitureRepository.loadModel(model) else {
            await MainActor.run {
                self.errorMessage = "家具モデルの読み込みに失敗しました: \(model.name)"
            }
            print("🔥 モデル読み込み失敗: \(model.name)")
            return
        }
        
        print("🔥 モデル読み込み成功: \(model.name)")
        
        // 床面にスナップした位置を計算
        let snappedPosition = snapToFloor(position: position, for: model)
        
        await MainActor.run {
            // PlacedFurnitureEntityを作成
            let furnitureEntity = PlacedFurnitureEntity(
                furnitureModel: model,
                modelEntity: modelEntity,
                at: snappedPosition
            )
            
            // ARViewに追加
            guard let arView = self.arView else { 
                print("ARViewが利用できません")
                return 
            }
            
            let anchorEntity = AnchorEntity(world: snappedPosition)
            anchorEntity.addChild(furnitureEntity)
            arView.scene.addAnchor(anchorEntity)
            
            // 管理リストに追加
            self.placedFurnitureEntities.append(furnitureEntity)
            
            print("🔥 家具配置完了: \(model.name) at \(snappedPosition)")
            print("🔥 配置済み家具数: \(self.placedFurnitureEntities.count)")
        }
    }
    
    /// 床面にスナップした位置を計算
    /// - Parameters:
    ///   - position: 元の位置
    ///   - model: 家具モデル
    /// - Returns: スナップされた位置
    private func snapToFloor(position: SIMD3<Float>, for model: FurnitureModel) -> SIMD3<Float> {
        // より正確な床面検出を試行
        let accurateFloorPosition = findAccurateFloorPosition(near: position)
        
        // 家具の高さの半分だけ上に配置（床面に接するように）
        let heightOffset = model.realWorldSize.height / 2
        
        var snappedPosition = accurateFloorPosition ?? position
        snappedPosition.y += heightOffset
        
        print("床面スナップ: \(position) -> \(snappedPosition) (オフセット: \(heightOffset))")
        return snappedPosition
    }
    
    /// より正確な床面位置を検出
    /// - Parameter position: 基準位置
    /// - Returns: 正確な床面位置、検出できない場合はnil
    private func findAccurateFloorPosition(near position: SIMD3<Float>) -> SIMD3<Float>? {
        // 検出された平面の中から最も近い平面を探す
        var closestPlane: ARPlaneAnchor?
        var closestDistance: Float = Float.greatestFiniteMagnitude
        
        for planeAnchor in detectedPlanes.values {
            // 平面の中心位置を計算
            let planeCenter = planeAnchor.center
            let planeWorldPosition = SIMD3<Float>(
                planeAnchor.transform.columns.3.x + planeCenter.x,
                planeAnchor.transform.columns.3.y + planeCenter.y,
                planeAnchor.transform.columns.3.z + planeCenter.z
            )
            
            // 水平距離を計算（Y軸は除外）
            let horizontalDistance = distance(
                SIMD2<Float>(position.x, position.z),
                SIMD2<Float>(planeWorldPosition.x, planeWorldPosition.z)
            )
            
            // 平面の範囲内かチェック
            let extent = planeAnchor.planeExtent
            if horizontalDistance <= max(extent.width, extent.height) / 2 {
                let totalDistance = distance(position, planeWorldPosition)
                if totalDistance < closestDistance {
                    closestDistance = totalDistance
                    closestPlane = planeAnchor
                }
            }
        }
        
        // 最も近い平面の表面位置を返す
        if let plane = closestPlane {
            let planeY = plane.transform.columns.3.y
            return SIMD3<Float>(position.x, planeY, position.z)
        }
        
        return nil
    }
    
    // MARK: - Furniture Management
    
    /// 選択された家具モデルを設定
    /// - Parameter model: 選択する家具モデル
    func selectFurnitureModel(_ model: FurnitureModel) {
        selectedFurnitureModel = model
        print("家具モデルを選択: \(model.name)")
    }
    
    /// 選択された家具を削除
    func deleteSelectedFurniture() {
        let selectedEntities = placedFurnitureEntities.filter { $0.isSelected }
        
        for entity in selectedEntities {
            // ARViewから削除
            entity.parent?.removeFromParent()
            
            // 管理リストから削除
            if let index = placedFurnitureEntities.firstIndex(where: { $0.placementId == entity.placementId }) {
                placedFurnitureEntities.remove(at: index)
            }
            
            print("家具を削除: \(entity.furnitureModel.name)")
        }
        
        print("削除完了。残り家具数: \(placedFurnitureEntities.count)")
    }
    
    /// すべての家具を削除
    func clearAllFurniture() {
        for entity in placedFurnitureEntities {
            entity.parent?.removeFromParent()
        }
        
        placedFurnitureEntities.removeAll()
        print("すべての家具を削除しました")
    }
    
    /// 配置済み家具の数を取得
    func getPlacedFurnitureCount() -> Int {
        return placedFurnitureEntities.count
    }
    
    /// 選択中の家具の数を取得
    func getSelectedFurnitureCount() -> Int {
        return placedFurnitureEntities.filter { $0.isSelected }.count
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