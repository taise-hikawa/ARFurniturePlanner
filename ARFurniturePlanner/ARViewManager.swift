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
import Darwin.Mach
import Combine

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
    
    // MARK: - Gesture Management Properties
    private var currentlySelectedEntity: PlacedFurnitureEntity?
    private var gestureStartTime: Date?
    private var performanceMonitor = GesturePerformanceMonitor()
    
    // MARK: - Furniture Management Properties
    @Published var selectedFurnitureModel: FurnitureModel?
    @Published var furnitureRepository = FurnitureRepository()
    
    // MARK: - Performance Monitoring Properties
    @Published var currentFPS: Double = 0.0
    @Published var memoryUsage: Double = 0.0
    @Published var isPerformanceOptimal: Bool = true
    private var performanceTimer: Timer?
    
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
            
            // パフォーマンス監視を開始
            self.startPerformanceMonitoring()
        }
    }
    
    /// ARSessionを停止
    func stopARSession() {
        arSession?.pause()
        Task { @MainActor in
            self.stopPerformanceMonitoring()
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
        
        // ジェスチャーを設定
        setupGestures()
        
        // 選択変更の通知を監視
        setupSelectionNotifications()
    }
    
    // MARK: - Gesture Setup
    
    /// すべてのジェスチャーを設定
    private func setupGestures() {
        guard let arView = arView else { return }
        
        // タップジェスチャーを設定
        setupTapGesture()
        
        // カスタムジェスチャーを設定
        setupCustomGestures()
        
        // RealityKitの組み込みジェスチャーを有効化
        setupRealityKitGestures()
        
        print("すべてのジェスチャーを設定しました")
    }
    
    /// カスタムジェスチャーを設定
    private func setupCustomGestures() {
        guard let arView = arView else { return }
        
        // パンジェスチャー（ドラッグ用）
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        arView.addGestureRecognizer(panGesture)
        
        // ピンチジェスチャー（スケール用）
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinchGesture)
        
        // 回転ジェスチャー
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        arView.addGestureRecognizer(rotationGesture)
        
        // ジェスチャー同時認識を許可
        panGesture.delegate = self
        pinchGesture.delegate = self
        rotationGesture.delegate = self
        
        print("カスタムジェスチャーを設定しました")
    }
    
    /// タップジェスチャーを設定
    private func setupTapGesture() {
        guard let arView = arView else { return }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        print("タップジェスチャーを設定しました")
    }
    
    /// RealityKitの組み込みジェスチャーを設定
    private func setupRealityKitGestures() {
        guard arView != nil else { return }
        
        // 配置済み家具にジェスチャーを適用
        for entity in placedFurnitureEntities {
            enableGesturesForEntity(entity)
        }
    }
    
    /// 特定のエンティティにジェスチャーを有効化
    /// - Parameter entity: ジェスチャーを有効化する家具エンティティ
    private func enableGesturesForEntity(_ entity: PlacedFurnitureEntity) {
        // RealityKitの組み込みジェスチャーを有効化
        // コリジョン形状を生成（ジェスチャー認識に必要）
        entity.generateCollisionShapes(recursive: true)
        
        // 基本的なジェスチャーを有効化
        arView?.installGestures([.translation, .rotation, .scale], for: entity)
        
        // カスタム制約はジェスチャーイベントハンドラーで適用
        setupGestureEventHandlers(for: entity)
        
        print("ジェスチャーを有効化: \(entity.furnitureModel.name)")
    }
    
    /// エンティティのジェスチャーイベントハンドラーを設定
    /// - Parameter entity: 対象エンティティ
    private func setupGestureEventHandlers(for entity: PlacedFurnitureEntity) {
        // RealityKitの基本ジェスチャーを使用
        // 制約は後でカスタムロジックで適用
        
        // ジェスチャー開始時の処理
        entity.beginGestureManipulation()
        
        print("ジェスチャーイベントハンドラーを設定: \(entity.furnitureModel.name)")
    }
    
    /// 選択変更通知を設定
    private func setupSelectionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFurnitureSelectionChanged(_:)),
            name: .furnitureSelectionChanged,
            object: nil
        )
    }
    
    /// 家具選択変更を処理
    /// - Parameter notification: 選択変更通知
    @objc private func handleFurnitureSelectionChanged(_ notification: Notification) {
        guard let entity = notification.object as? PlacedFurnitureEntity,
              let isSelected = notification.userInfo?["isSelected"] as? Bool else {
            return
        }
        
        if isSelected {
            // 新しく選択されたエンティティを設定
            currentlySelectedEntity = entity
            
            // 他のエンティティの選択を解除
            for furnitureEntity in placedFurnitureEntities {
                if furnitureEntity != entity && furnitureEntity.isSelected {
                    furnitureEntity.deselect()
                }
            }
            
            print("家具が選択されました: \(entity.furnitureModel.name)")
        } else {
            // 選択解除
            if currentlySelectedEntity == entity {
                currentlySelectedEntity = nil
            }
            print("家具の選択が解除されました: \(entity.furnitureModel.name)")
        }
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
        
        // 家具以外の場所をタップした場合、すべての選択を解除
        deselectAllFurniture()
        
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
        
        // 家具エンティティのみを抽出し、距離でソート
        var furnitureHits: [(entity: PlacedFurnitureEntity, distance: Float)] = []
        
        for result in results {
            // 家具エンティティまたはその子エンティティかチェック
            var currentEntity: Entity? = result.entity
            
            while currentEntity != nil {
                if let furnitureEntity = currentEntity as? PlacedFurnitureEntity {
                    // カメラからの距離を計算
                    let cameraPosition = arView.cameraTransform.translation
                    let entityPosition = furnitureEntity.position
                    let distance = distance(cameraPosition, entityPosition)
                    
                    furnitureHits.append((entity: furnitureEntity, distance: distance))
                    break // 同じエンティティを重複して追加しないように
                }
                currentEntity = currentEntity?.parent
            }
        }
        
        // 最も近い家具エンティティを返す
        let closestHit = furnitureHits.min { $0.distance < $1.distance }
        
        if let closest = closestHit {
            print("タップされた家具: \(closest.entity.furnitureModel.name) (距離: \(String(format: "%.2f", closest.distance))m)")
            return closest.entity
        }
        
        return nil
    }
    
    /// 家具エンティティ間の干渉チェック
    /// - Parameters:
    ///   - entity1: チェック対象の家具エンティティ1
    ///   - entity2: チェック対象の家具エンティティ2
    /// - Returns: 干渉している場合はtrue
    private func checkFurnitureInterference(_ entity1: PlacedFurnitureEntity, _ entity2: PlacedFurnitureEntity) -> Bool {
        return entity1.isColliding(with: entity2)
    }
    
    /// 選択精度を向上させるための追加チェック
    /// - Parameter location: タップ位置
    /// - Returns: 最も適切な家具エンティティ
    private func getAccurateTappedEntity(at location: CGPoint) -> PlacedFurnitureEntity? {
        guard let arView = arView else { return nil }
        
        // 画面座標からワールド座標へのレイを作成
        guard let ray = arView.ray(through: location) else { return nil }
        
        var bestEntity: PlacedFurnitureEntity?
        var bestDistance: Float = Float.greatestFiniteMagnitude
        
        // 各家具エンティティとの交差をチェック
        for entity in placedFurnitureEntities {
            // エンティティの境界ボックスとレイの交差をチェック
            if let bounds = entity.getWorldBounds() {
                let intersectionDistance = calculateRayBoxIntersection(ray: ray, bounds: bounds)
                
                if intersectionDistance >= 0 && intersectionDistance < bestDistance {
                    bestDistance = intersectionDistance
                    bestEntity = entity
                }
            }
        }
        
        return bestEntity
    }
    
    /// レイと境界ボックスの交差距離を計算
    /// - Parameters:
    ///   - ray: レイ
    ///   - bounds: 境界ボックス
    /// - Returns: 交差距離、交差しない場合は-1
    private func calculateRayBoxIntersection(ray: (origin: SIMD3<Float>, direction: SIMD3<Float>), bounds: BoundingBox) -> Float {
        let invDir = SIMD3<Float>(1.0 / ray.direction.x, 1.0 / ray.direction.y, 1.0 / ray.direction.z)
        
        let t1 = (bounds.min - ray.origin) * invDir
        let t2 = (bounds.max - ray.origin) * invDir
        
        let tmin = max(max(min(t1.x, t2.x), min(t1.y, t2.y)), min(t1.z, t2.z))
        let tmax = min(min(max(t1.x, t2.x), max(t1.y, t2.y)), max(t1.z, t2.z))
        
        // レイが境界ボックスと交差する場合
        if tmax >= 0 && tmin <= tmax {
            return tmin >= 0 ? tmin : tmax
        }
        
        return -1 // 交差しない
    }
    
    /// 家具エンティティのタップを処理
    /// - Parameter entity: タップされた家具エンティティ
    private func handleFurnitureEntityTap(_ entity: PlacedFurnitureEntity) {
        // 既に選択されている場合は選択解除、そうでなければ選択
        if entity.isSelected {
            entity.deselect()
            currentlySelectedEntity = nil
        } else {
            // 他の家具の選択を解除
            deselectAllFurniture()
            
            // タップされた家具を選択
            entity.select()
            currentlySelectedEntity = entity
        }
        
        print("家具エンティティをタップ: \(entity.furnitureModel.name) (選択: \(entity.isSelected))")
    }
    
    /// すべての家具の選択を解除
    private func deselectAllFurniture() {
        for furnitureEntity in placedFurnitureEntities {
            if furnitureEntity.isSelected {
                furnitureEntity.deselect()
            }
        }
        currentlySelectedEntity = nil
        print("すべての家具の選択を解除しました")
    }
    
    /// 選択中の家具エンティティを取得
    /// - Returns: 現在選択中の家具エンティティ、存在しない場合はnil
    func getCurrentlySelectedEntity() -> PlacedFurnitureEntity? {
        return currentlySelectedEntity
    }
    
    /// 特定の家具を選択
    /// - Parameter entity: 選択する家具エンティティ
    func selectFurnitureEntity(_ entity: PlacedFurnitureEntity) {
        // 他の家具の選択を解除
        deselectAllFurniture()
        
        // 指定された家具を選択
        entity.select()
        currentlySelectedEntity = entity
        
        print("家具を選択: \(entity.furnitureModel.name)")
    }
    
    /// 家具の選択を解除
    /// - Parameter entity: 選択解除する家具エンティティ
    func deselectFurnitureEntity(_ entity: PlacedFurnitureEntity) {
        entity.deselect()
        
        if currentlySelectedEntity == entity {
            currentlySelectedEntity = nil
        }
        
        print("家具の選択を解除: \(entity.furnitureModel.name)")
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
            
            // 新しく配置された家具にジェスチャーを有効化
            self.enableGesturesForEntity(furnitureEntity)
            
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
    
    // MARK: - Performance Optimization
    
    /// パフォーマンス監視を開始
    private func startPerformanceMonitoring() {
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePerformanceMetrics()
            }
        }
    }
    
    /// パフォーマンス監視を停止
    private func stopPerformanceMonitoring() {
        performanceTimer?.invalidate()
        performanceTimer = nil
    }
    
    /// パフォーマンス指標を更新
    private func updatePerformanceMetrics() {
        // FPS計算
        currentFPS = performanceMonitor.getAverageFPS()
        
        // メモリ使用量計算
        memoryUsage = getCurrentMemoryUsage()
        
        // パフォーマンス状態の判定
        isPerformanceOptimal = currentFPS >= 30.0 && memoryUsage < 200.0 // 200MB以下
        
        // パフォーマンスが低下している場合の自動調整
        if !isPerformanceOptimal {
            optimizePerformance()
        }
    }
    
    /// 現在のメモリ使用量を取得（MB単位）
    /// - Returns: メモリ使用量（MB）
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // バイトからMBに変換
        }
        
        return 0.0
    }
    
    /// パフォーマンス最適化を実行
    private func optimizePerformance() {
        print("パフォーマンス最適化を実行中...")
        
        // 1. 不要なリソースの解放
        cleanupUnusedResources()
        
        // 2. 品質設定の調整
        adjustQualitySettings()
        
        // 3. ジェスチャー処理の最適化
        optimizeGestureProcessing()
        
        print("パフォーマンス最適化完了")
    }
    
    /// 不要なリソースをクリーンアップ
    private func cleanupUnusedResources() {
        // 家具リポジトリのキャッシュをクリア
        furnitureRepository.clearCache()
        
        // 使用されていない平面可視化エンティティを削除
        cleanupUnusedPlaneEntities()
        
        // メモリ警告を発行してシステムにクリーンアップを促す
        DispatchQueue.main.async {
            // システムのメモリクリーンアップを促進
            autoreleasepool {
                // 自動解放プールを使用してメモリを解放
            }
        }
    }
    
    /// 使用されていない平面エンティティをクリーンアップ
    private func cleanupUnusedPlaneEntities() {
        let currentPlaneIds = Set(detectedPlanes.keys)
        let entityPlaneIds = Set(planeEntities.keys)
        
        // 検出されていない平面のエンティティを削除
        let unusedIds = entityPlaneIds.subtracting(currentPlaneIds)
        for unusedId in unusedIds {
            if let entity = planeEntities[unusedId] {
                entity.removeFromParent()
                planeEntities.removeValue(forKey: unusedId)
            }
        }
        
        if !unusedIds.isEmpty {
            print("未使用の平面エンティティを削除: \(unusedIds.count)個")
        }
    }
    
    /// 品質設定を調整
    private func adjustQualitySettings() {
        guard let arView = arView else { return }
        
        if currentFPS < 25.0 {
            // FPSが25未満の場合、品質を下げる
            arView.renderOptions.remove(.disableMotionBlur)
            arView.renderOptions.remove(.disableHDR)
            
            // 影の品質を下げる
            for entity in placedFurnitureEntities {
                entity.setShadowVisible(false)
            }
            
            print("品質設定を下げました（FPS向上のため）")
        } else if currentFPS > 45.0 {
            // FPSが45以上の場合、品質を上げる
            arView.renderOptions.insert(.disableMotionBlur)
            arView.renderOptions.insert(.disableHDR)
            
            // 影を有効化
            for entity in placedFurnitureEntities {
                entity.setShadowVisible(true)
            }
            
            print("品質設定を上げました（余裕があるため）")
        }
    }
    
    /// ジェスチャー処理を最適化
    private func optimizeGestureProcessing() {
        // ジェスチャー処理中のパフォーマンスが低い場合
        if performanceMonitor.getMinimumFPS() < 20.0 {
            // ジェスチャーの更新頻度を下げる
            for entity in placedFurnitureEntities {
                if entity.isBeingManipulated {
                    // 操作中のエンティティのハイライトを一時的に無効化
                    entity.hideHighlight()
                }
            }
            
            print("ジェスチャー処理を最適化しました")
        }
    }
    
    /// メモリ使用量を監視し、制限を超えた場合に警告
    private func monitorMemoryUsage() {
        let maxMemoryMB: Double = 300.0 // 300MB制限
        
        if memoryUsage > maxMemoryMB {
            print("警告: メモリ使用量が制限を超えています (\(String(format: "%.1f", memoryUsage))MB)")
            
            // 緊急メモリクリーンアップ
            emergencyMemoryCleanup()
        }
    }
    
    /// 緊急メモリクリーンアップ
    private func emergencyMemoryCleanup() {
        print("緊急メモリクリーンアップを実行中...")
        
        // すべてのキャッシュをクリア
        furnitureRepository.clearCache()
        
        // 平面可視化を無効化
        if showPlaneVisualization {
            togglePlaneVisualization()
        }
        
        // 影を無効化
        for entity in placedFurnitureEntities {
            entity.setShadowVisible(false)
        }
        
        // ハイライトを無効化
        for entity in placedFurnitureEntities {
            entity.hideHighlight()
        }
        
        print("緊急メモリクリーンアップ完了")
    }
    
    /// パフォーマンス統計を取得
    /// - Returns: パフォーマンス統計の辞書
    func getPerformanceStats() -> [String: Any] {
        return [
            "currentFPS": currentFPS,
            "averageFPS": performanceMonitor.getAverageFPS(),
            "minimumFPS": performanceMonitor.getMinimumFPS(),
            "memoryUsage": memoryUsage,
            "isOptimal": isPerformanceOptimal,
            "furnitureCount": placedFurnitureEntities.count,
            "planeCount": detectedPlanes.count
        ]
    }
    
    // MARK: - Cleanup
    deinit {
        arSession?.pause()
        performanceTimer?.invalidate()
        performanceTimer = nil
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Custom Gesture Handlers

extension ARViewManager {
    
    /// パンジェスチャーを処理（ドラッグ移動）
    /// - Parameter gesture: パンジェスチャー
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let arView = arView,
              let selectedEntity = currentlySelectedEntity else { return }
        
        let location = gesture.location(in: arView)
        
        switch gesture.state {
        case .began:
            handleGestureBegin(for: selectedEntity)
            
        case .changed:
            // レイキャストで新しい位置を計算
            if let query = arView.makeRaycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal) {
                let results = arView.session.raycast(query)
                if let result = results.first {
                    let newPosition = SIMD3<Float>(result.worldTransform.columns.3.x,
                                                 result.worldTransform.columns.3.y,
                                                 result.worldTransform.columns.3.z)
                    
                    // 制約を適用
                    let constrainedPosition = constrainTranslation(for: selectedEntity, proposedPosition: newPosition)
                    selectedEntity.setPositionImmediate(constrainedPosition)
                    
                    handleGestureUpdate(for: selectedEntity)
                }
            }
            
        case .ended, .cancelled:
            handleGestureEnd(for: selectedEntity)
            
        default:
            break
        }
    }
    
    /// ピンチジェスチャーを処理（スケール変更）
    /// - Parameter gesture: ピンチジェスチャー
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let selectedEntity = currentlySelectedEntity else { return }
        
        switch gesture.state {
        case .began:
            handleGestureBegin(for: selectedEntity)
            
        case .changed:
            let scale = Float(gesture.scale)
            let currentScale = selectedEntity.scale.x // 現在のスケール
            let newScale = currentScale * scale
            
            // 制約を適用
            let constrainedScale = constrainScale(for: selectedEntity, proposedScale: newScale)
            selectedEntity.setScaleImmediate(constrainedScale)
            
            // ジェスチャーのスケールをリセット
            gesture.scale = 1.0
            
            handleGestureUpdate(for: selectedEntity)
            
        case .ended, .cancelled:
            handleGestureEnd(for: selectedEntity)
            
        default:
            break
        }
    }
    
    /// 回転ジェスチャーを処理（Y軸回転）
    /// - Parameter gesture: 回転ジェスチャー
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let selectedEntity = currentlySelectedEntity else { return }
        
        switch gesture.state {
        case .began:
            handleGestureBegin(for: selectedEntity)
            
        case .changed:
            let rotation = Float(gesture.rotation)
            
            // Y軸回転のみを適用
            let yRotation = simd_quatf(angle: rotation, axis: SIMD3<Float>(0, 1, 0))
            let newRotation = selectedEntity.orientation * yRotation
            
            // 制約を適用（Y軸のみ）
            let constrainedRotation = constrainRotation(for: selectedEntity, proposedRotation: newRotation)
            selectedEntity.setRotationImmediate(constrainedRotation)
            
            // ジェスチャーの回転をリセット
            gesture.rotation = 0.0
            
            handleGestureUpdate(for: selectedEntity)
            
        case .ended, .cancelled:
            handleGestureEnd(for: selectedEntity)
            
        default:
            break
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ARViewManager: UIGestureRecognizerDelegate {
    
    /// 複数のジェスチャーの同時認識を許可
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // ピンチと回転は同時に認識可能
        if (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer) ||
           (gestureRecognizer is UIRotationGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer) {
            return true
        }
        
        // パンジェスチャーは単独で実行
        return false
    }
    
    /// ジェスチャーの開始を制御
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 選択されたエンティティがある場合のみジェスチャーを有効化
        return currentlySelectedEntity != nil
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

// MARK: - Gesture Performance Monitor

/// ジェスチャー操作のパフォーマンスを監視するクラス
class GesturePerformanceMonitor {
    private var frameCount: Int = 0
    private var lastFrameTime: Date = Date()
    private var fpsHistory: [Double] = []
    private let maxHistorySize = 30 // 30フレーム分の履歴
    
    /// フレーム更新を記録
    func recordFrame() {
        let currentTime = Date()
        let deltaTime = currentTime.timeIntervalSince(lastFrameTime)
        
        if deltaTime > 0 {
            let fps = 1.0 / deltaTime
            fpsHistory.append(fps)
            
            // 履歴サイズを制限
            if fpsHistory.count > maxHistorySize {
                fpsHistory.removeFirst()
            }
        }
        
        lastFrameTime = currentTime
        frameCount += 1
    }
    
    /// 平均FPSを取得
    /// - Returns: 平均FPS
    func getAverageFPS() -> Double {
        guard !fpsHistory.isEmpty else { return 0.0 }
        return fpsHistory.reduce(0, +) / Double(fpsHistory.count)
    }
    
    /// 最小FPSを取得
    /// - Returns: 最小FPS
    func getMinimumFPS() -> Double {
        return fpsHistory.min() ?? 0.0
    }
    
    /// パフォーマンスが要件を満たしているかチェック
    /// - Returns: 30FPS以上を維持している場合はtrue
    func isPerformanceAcceptable() -> Bool {
        return getMinimumFPS() >= 30.0
    }
    
    /// パフォーマンス統計をリセット
    func reset() {
        frameCount = 0
        fpsHistory.removeAll()
        lastFrameTime = Date()
    }
}

// MARK: - ARViewManager Gesture Event Handling

extension ARViewManager {
    
    /// ジェスチャー開始時の処理
    /// - Parameter entity: 操作対象のエンティティ
    func handleGestureBegin(for entity: PlacedFurnitureEntity) {
        gestureStartTime = Date()
        entity.beginGestureManipulation()
        performanceMonitor.reset()
        
        print("ジェスチャー操作開始: \(entity.furnitureModel.name)")
    }
    
    /// ジェスチャー更新時の処理
    /// - Parameter entity: 操作対象のエンティティ
    func handleGestureUpdate(for entity: PlacedFurnitureEntity) {
        performanceMonitor.recordFrame()
        
        // パフォーマンス監視
        if !performanceMonitor.isPerformanceAcceptable() {
            print("警告: ジェスチャー操作中のパフォーマンスが低下しています (FPS: \(performanceMonitor.getMinimumFPS()))")
        }
    }
    
    /// ジェスチャー終了時の処理
    /// - Parameter entity: 操作対象のエンティティ
    func handleGestureEnd(for entity: PlacedFurnitureEntity) {
        entity.endGestureManipulation()
        
        if let startTime = gestureStartTime {
            let duration = Date().timeIntervalSince(startTime)
            let avgFPS = performanceMonitor.getAverageFPS()
            let minFPS = performanceMonitor.getMinimumFPS()
            
            print("ジェスチャー操作完了: \(entity.furnitureModel.name)")
            print("操作時間: \(String(format: "%.2f", duration))秒")
            print("平均FPS: \(String(format: "%.1f", avgFPS))")
            print("最小FPS: \(String(format: "%.1f", minFPS))")
        }
        
        gestureStartTime = nil
    }
    
    /// 移動ジェスチャーの制約を適用
    /// - Parameters:
    ///   - entity: 操作対象のエンティティ
    ///   - proposedPosition: 提案された新しい位置
    /// - Returns: 制約を適用した位置
    func constrainTranslation(for entity: PlacedFurnitureEntity, proposedPosition: SIMD3<Float>) -> SIMD3<Float> {
        // 最も近い平面のY座標を取得
        let nearestPlaneY = findNearestPlaneY(to: proposedPosition) ?? proposedPosition.y
        
        // 平面上に制限
        return entity.validatePosition(proposedPosition, onPlaneY: nearestPlaneY)
    }
    
    /// 回転ジェスチャーの制約を適用
    /// - Parameters:
    ///   - entity: 操作対象のエンティティ
    ///   - proposedRotation: 提案された新しい回転
    /// - Returns: 制約を適用した回転（Y軸のみ）
    func constrainRotation(for entity: PlacedFurnitureEntity, proposedRotation: simd_quatf) -> simd_quatf {
        return entity.validateRotation(proposedRotation)
    }
    
    /// スケールジェスチャーの制約を適用
    /// - Parameters:
    ///   - entity: 操作対象のエンティティ
    ///   - proposedScale: 提案された新しいスケール
    /// - Returns: 制約を適用したスケール
    func constrainScale(for entity: PlacedFurnitureEntity, proposedScale: Float) -> Float {
        return entity.validateScale(proposedScale)
    }
    
    /// 指定位置に最も近い平面のY座標を取得
    /// - Parameter position: 基準位置
    /// - Returns: 最も近い平面のY座標、見つからない場合はnil
    private func findNearestPlaneY(to position: SIMD3<Float>) -> Float? {
        var nearestY: Float?
        var nearestDistance: Float = Float.greatestFiniteMagnitude
        
        for planeAnchor in detectedPlanes.values {
            let planeY = planeAnchor.transform.columns.3.y
            let distance = abs(position.y - planeY)
            
            if distance < nearestDistance {
                nearestDistance = distance
                nearestY = planeY
            }
        }
        
        return nearestY
    }
    
    /// ジェスチャー競合を回避
    /// - Parameter entity: 操作対象のエンティティ
    func resolveGestureConflicts(for entity: PlacedFurnitureEntity) {
        // 他のエンティティが操作中の場合は、そのジェスチャーを無効化
        for otherEntity in placedFurnitureEntities {
            if otherEntity != entity && otherEntity.isBeingManipulated {
                otherEntity.endGestureManipulation()
                print("ジェスチャー競合を解決: \(otherEntity.furnitureModel.name)の操作を終了")
            }
        }
    }
}