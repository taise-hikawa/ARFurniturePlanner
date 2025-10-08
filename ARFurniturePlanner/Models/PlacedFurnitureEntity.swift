//
//  PlacedFurnitureEntity.swift
//  ARFurniturePlanner
//
//  Created by Kiro on 2025/10/09.
//

import Foundation
import RealityKit
import simd
import UIKit

/// 配置された家具のエンティティを管理するクラス
class PlacedFurnitureEntity: Entity, HasModel, HasCollision {
    
    // MARK: - Properties
    let furnitureModel: FurnitureModel
    let placementId: UUID
    private var isSelectedState: Bool = false
    private var highlightEntity: ModelEntity?
    private var shadowEntity: ModelEntity?
    private var placementAnimationDuration: TimeInterval = 0.5
    
    // MARK: - Published Properties (for UI binding)
    var isSelected: Bool {
        get { isSelectedState }
        set {
            if newValue != isSelectedState {
                isSelectedState = newValue
                updateHighlight()
            }
        }
    }
    
    // MARK: - Initialization
    
    /// PlacedFurnitureEntityを初期化
    /// - Parameters:
    ///   - furnitureModel: 家具モデル
    ///   - modelEntity: 3Dモデルエンティティ
    ///   - position: 配置位置
    init(furnitureModel: FurnitureModel, modelEntity: ModelEntity, at position: SIMD3<Float>) {
        self.furnitureModel = furnitureModel
        self.placementId = UUID()
        
        super.init()
        
        // ModelEntityを子として追加
        addChild(modelEntity)
        
        // 位置を設定
        self.position = position
        
        // 名前を設定
        self.name = "PlacedFurniture_\(furnitureModel.name)_\(placementId.uuidString.prefix(8))"
        
        // コリジョン形状を設定
        setupCollision()
        
        // 影を生成
        setupShadow()
        
        // 配置アニメーションを実行
        playPlacementAnimation()
        
        print("家具エンティティを作成: \(furnitureModel.name) at \(position)")
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
    
    // MARK: - Selection Management
    
    /// エンティティを選択状態にする
    func select() {
        isSelected = true
        print("家具を選択: \(furnitureModel.name)")
    }
    
    /// エンティティの選択を解除する
    func deselect() {
        isSelected = false
        print("家具の選択を解除: \(furnitureModel.name)")
    }
    
    /// 選択状態を切り替える
    func toggleSelection() {
        isSelected = !isSelected
    }
    
    // MARK: - Highlight Management
    
    /// ハイライト表示を更新
    private func updateHighlight() {
        if isSelected {
            showHighlight()
        } else {
            hideHighlight()
        }
    }
    
    /// ハイライト表示を表示
    func showHighlight() {
        // 既存のハイライトを削除
        hideHighlight()
        
        // ハイライト用のアウトラインエンティティを作成
        guard let modelEntity = children.first as? ModelEntity,
              let mesh = modelEntity.model?.mesh else {
            print("警告: ハイライト作成に必要なメッシュが見つかりません")
            return
        }
        
        // ハイライト用マテリアル（発光する青色）
        var highlightMaterial = SimpleMaterial()
        highlightMaterial.color = .init(tint: .systemBlue.withAlphaComponent(0.3))
        highlightMaterial.roughness = MaterialScalarParameter(floatLiteral: 0.0)
        highlightMaterial.metallic = MaterialScalarParameter(floatLiteral: 1.0)
        
        // ハイライトエンティティを作成（少し大きくしてアウトライン効果）
        highlightEntity = ModelEntity(mesh: mesh, materials: [highlightMaterial])
        highlightEntity?.scale = SIMD3<Float>(repeating: 1.05) // 5%大きく
        highlightEntity?.name = "Highlight_\(furnitureModel.name)"
        
        // ハイライトを子として追加（背景に表示）
        if let highlight = highlightEntity {
            addChild(highlight)
        }
        
        print("ハイライト表示: \(furnitureModel.name)")
    }
    
    /// ハイライト表示を非表示
    func hideHighlight() {
        highlightEntity?.removeFromParent()
        highlightEntity = nil
    }
    
    // MARK: - Transform Operations
    
    /// 位置を更新（アニメーション付き）
    /// - Parameter newPosition: 新しい位置
    func updatePosition(_ newPosition: SIMD3<Float>) {
        animateMovement(to: newPosition)
    }
    
    /// 位置を即座に更新（アニメーションなし）
    /// - Parameter newPosition: 新しい位置
    func setPositionImmediate(_ newPosition: SIMD3<Float>) {
        position = newPosition
        print("家具位置を即座に更新: \(furnitureModel.name) to \(newPosition)")
    }
    
    /// スケールを更新（アニメーション付き）
    /// - Parameter newScale: 新しいスケール
    func updateScale(_ newScale: Float) {
        animateScaleChange(to: newScale)
    }
    
    /// スケールを即座に更新（アニメーションなし）
    /// - Parameter newScale: 新しいスケール
    func setScaleImmediate(_ newScale: Float) {
        let clampedScale = max(furnitureModel.minScale, min(furnitureModel.maxScale, newScale))
        scale = SIMD3<Float>(repeating: clampedScale)
        
        // ハイライトのスケールも更新
        highlightEntity?.scale = SIMD3<Float>(repeating: clampedScale * 1.05)
        
        // 影のスケールも更新
        updateShadowScale(clampedScale)
        
        print("家具スケールを即座に更新: \(furnitureModel.name) to \(clampedScale)")
    }
    
    /// 回転を更新（Y軸のみ、アニメーション付き）
    /// - Parameter yRotation: Y軸回転角度（ラジアン）
    func updateRotation(yRotation: Float) {
        let rotation = simd_quatf(angle: yRotation, axis: SIMD3<Float>(0, 1, 0))
        animateRotation(to: rotation)
    }
    
    /// 回転を更新（クォータニオン、アニメーション付き）
    /// - Parameter rotation: 新しい回転クォータニオン
    func updateRotation(_ rotation: simd_quatf) {
        animateRotation(to: rotation)
    }
    
    /// 回転を即座に更新（アニメーションなし）
    /// - Parameter rotation: 新しい回転クォータニオン
    func setRotationImmediate(_ rotation: simd_quatf) {
        orientation = rotation
        print("家具回転を即座に更新: \(furnitureModel.name)")
    }
    
    // MARK: - Collision Setup
    
    /// コリジョン形状を設定
    private func setupCollision() {
        // 家具モデルのサイズに基づいてボックスコリジョンを作成
        let size = furnitureModel.boundingBoxSize
        let collisionShape = ShapeResource.generateBox(size: size)
        
        // コリジョンコンポーネントを追加
        collision = CollisionComponent(shapes: [collisionShape])
        
        print("コリジョン設定完了: \(furnitureModel.name) サイズ: \(size)")
    }
    
    // MARK: - Shadow Management
    
    /// 影を設定
    private func setupShadow() {
        // 影用の平面メッシュを作成（家具の底面サイズに基づく）
        let shadowSize = max(furnitureModel.realWorldSize.width, furnitureModel.realWorldSize.depth)
        let shadowMesh = MeshResource.generatePlane(width: shadowSize * 0.8, depth: shadowSize * 0.8)
        
        // 影用マテリアル（半透明の黒）
        var shadowMaterial = SimpleMaterial()
        shadowMaterial.color = .init(tint: .black.withAlphaComponent(0.3))
        shadowMaterial.roughness = MaterialScalarParameter(floatLiteral: 1.0)
        shadowMaterial.metallic = MaterialScalarParameter(floatLiteral: 0.0)
        
        // 影エンティティを作成
        shadowEntity = ModelEntity(mesh: shadowMesh, materials: [shadowMaterial])
        shadowEntity?.name = "Shadow_\(furnitureModel.name)"
        
        // 影を床面に配置（家具の真下、少し下に）
        let shadowOffset: Float = -furnitureModel.realWorldSize.height / 2 - 0.001 // 1mm下
        shadowEntity?.position = SIMD3<Float>(0, shadowOffset, 0)
        
        // X軸で90度回転（水平に）
        shadowEntity?.orientation = simd_quatf(angle: -.pi/2, axis: SIMD3<Float>(1, 0, 0))
        
        // 影を追加
        if let shadow = shadowEntity {
            addChild(shadow)
        }
        
        print("影を設定: \(furnitureModel.name) サイズ: \(shadowSize)")
    }
    
    /// 影の表示/非表示を切り替え
    /// - Parameter visible: 表示するかどうか
    func setShadowVisible(_ visible: Bool) {
        shadowEntity?.isEnabled = visible
    }
    
    /// 影のサイズを更新
    /// - Parameter scale: スケール係数
    private func updateShadowScale(_ scale: Float) {
        shadowEntity?.scale = SIMD3<Float>(repeating: scale)
    }
    
    // MARK: - Placement Animation
    
    /// 配置時のアニメーションを実行
    private func playPlacementAnimation() {
        // 初期状態: 小さくして上から落下
        let initialScale = SIMD3<Float>(repeating: 0.1)
        let initialPosition = position + SIMD3<Float>(0, 0.5, 0) // 50cm上から
        
        // 初期状態を設定
        scale = initialScale
        position = initialPosition
        
        // アニメーション: スケールアップと落下
        let finalScale = SIMD3<Float>(repeating: 1.0)
        let finalPosition = position - SIMD3<Float>(0, 0.5, 0) // 元の位置に
        
        // RealityKitのアニメーションを使用
        let scaleAnimation = FromToByAnimation<Transform>(
            name: "scaleUp",
            from: .init(scale: initialScale, rotation: orientation, translation: initialPosition),
            to: .init(scale: finalScale, rotation: orientation, translation: finalPosition),
            duration: placementAnimationDuration,
            timing: .easeOut,
            bindTarget: .transform
        )
        
        // アニメーションを開始
        if let animationResource = try? AnimationResource.generate(with: scaleAnimation) {
            playAnimation(animationResource)
        }
        
        print("配置アニメーション開始: \(furnitureModel.name)")
    }
    
    /// スケール変更時のアニメーション
    /// - Parameter newScale: 新しいスケール
    func animateScaleChange(to newScale: Float) {
        let clampedScale = max(furnitureModel.minScale, min(furnitureModel.maxScale, newScale))
        let targetScale = SIMD3<Float>(repeating: clampedScale)
        
        // スケールアニメーション
        let scaleAnimation = FromToByAnimation<Transform>(
            name: "scaleChange",
            from: .init(scale: scale, rotation: orientation, translation: position),
            to: .init(scale: targetScale, rotation: orientation, translation: position),
            duration: 0.3,
            timing: .easeInOut,
            bindTarget: .transform
        )
        
        // 影のスケールも更新
        updateShadowScale(clampedScale)
        
        // アニメーションを開始
        if let animationResource = try? AnimationResource.generate(with: scaleAnimation) {
            playAnimation(animationResource)
        }
        
        print("スケールアニメーション: \(furnitureModel.name) to \(clampedScale)")
    }
    
    /// 回転アニメーション
    /// - Parameter targetRotation: 目標回転
    func animateRotation(to targetRotation: simd_quatf) {
        let rotationAnimation = FromToByAnimation<Transform>(
            name: "rotation",
            from: .init(scale: scale, rotation: orientation, translation: position),
            to: .init(scale: scale, rotation: targetRotation, translation: position),
            duration: 0.4,
            timing: .easeInOut,
            bindTarget: .transform
        )
        
        // アニメーションを開始
        if let animationResource = try? AnimationResource.generate(with: rotationAnimation) {
            playAnimation(animationResource)
        }
        
        print("回転アニメーション: \(furnitureModel.name)")
    }
    
    /// 位置移動アニメーション
    /// - Parameter targetPosition: 目標位置
    func animateMovement(to targetPosition: SIMD3<Float>) {
        let moveAnimation = FromToByAnimation<Transform>(
            name: "movement",
            from: .init(scale: scale, rotation: orientation, translation: position),
            to: .init(scale: scale, rotation: orientation, translation: targetPosition),
            duration: 0.3,
            timing: .easeInOut,
            bindTarget: .transform
        )
        
        // アニメーションを開始
        if let animationResource = try? AnimationResource.generate(with: moveAnimation) {
            playAnimation(animationResource)
        }
        
        print("移動アニメーション: \(furnitureModel.name) to \(targetPosition)")
    }
    
    // MARK: - Utility Methods
    
    /// エンティティの境界ボックスを取得
    /// - Returns: ワールド座標での境界ボックス
    func getWorldBounds() -> BoundingBox? {
        guard let modelEntity = children.first as? ModelEntity,
              let bounds = modelEntity.model?.mesh.bounds else {
            return nil
        }
        
        // ローカル座標からワールド座標に変換
        let transform = transform.matrix
        let min = transform * SIMD4<Float>(bounds.min, 1.0)
        let max = transform * SIMD4<Float>(bounds.max, 1.0)
        
        return BoundingBox(min: SIMD3<Float>(min.x, min.y, min.z), 
                          max: SIMD3<Float>(max.x, max.y, max.z))
    }
    
    /// 他の家具との衝突をチェック
    /// - Parameter otherEntity: チェック対象の他の家具エンティティ
    /// - Returns: 衝突している場合はtrue
    func isColliding(with otherEntity: PlacedFurnitureEntity) -> Bool {
        guard let myBounds = getWorldBounds(),
              let otherBounds = otherEntity.getWorldBounds() else {
            return false
        }
        
        // 境界ボックスの重複をチェック
        let xOverlap = myBounds.min.x <= otherBounds.max.x && myBounds.max.x >= otherBounds.min.x
        let yOverlap = myBounds.min.y <= otherBounds.max.y && myBounds.max.y >= otherBounds.min.y
        let zOverlap = myBounds.min.z <= otherBounds.max.z && myBounds.max.z >= otherBounds.min.z
        
        return xOverlap && yOverlap && zOverlap
    }
    
    /// 床面からの距離を取得
    /// - Returns: 床面からの距離（メートル）
    func getDistanceFromFloor() -> Float {
        return position.y
    }
    
    /// エンティティの情報を文字列で取得（デバッグ用）
    /// - Returns: エンティティ情報の文字列
    func getDebugInfo() -> String {
        return """
        家具: \(furnitureModel.name)
        ID: \(placementId)
        位置: \(position)
        スケール: \(scale)
        選択状態: \(isSelected)
        """
    }
    
    // MARK: - Cleanup
    
    deinit {
        hideHighlight()
        shadowEntity?.removeFromParent()
        shadowEntity = nil
        print("PlacedFurnitureEntity解放: \(furnitureModel.name)")
    }
}