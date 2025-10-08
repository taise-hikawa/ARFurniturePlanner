//
//  TestModelGenerator.swift
//  ARFurniturePlanner
//
//  Created by Kiro on 2025/10/09.
//

import Foundation
import RealityKit
import simd
import UIKit

/// テスト用3Dモデルを生成するユーティリティクラス
class TestModelGenerator {
    
    // MARK: - Model Generation
    
    /// テスト用キューブモデルを生成
    /// - Parameters:
    ///   - size: キューブのサイズ（メートル）
    ///   - color: キューブの色
    /// - Returns: 生成されたModelEntity
    static func generateTestCube(size: Float = 0.5, color: UIColor = .systemBlue) -> ModelEntity {
        // キューブメッシュを生成
        let mesh = MeshResource.generateBox(size: size)
        
        // マテリアルを作成
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = MaterialScalarParameter(floatLiteral: 0.3)
        material.metallic = MaterialScalarParameter(floatLiteral: 0.1)
        
        // ModelEntityを作成
        let entity = ModelEntity(mesh: mesh, materials: [material])
        
        // コリジョン形状を設定
        entity.generateCollisionShapes(recursive: true)
        
        // 名前を設定
        entity.name = "TestCube"
        
        print("テストキューブを生成: サイズ \(size)m")
        return entity
    }
    
    /// テスト用球体モデルを生成
    /// - Parameters:
    ///   - radius: 球体の半径（メートル）
    ///   - color: 球体の色
    /// - Returns: 生成されたModelEntity
    static func generateTestSphere(radius: Float = 0.3, color: UIColor = .systemRed) -> ModelEntity {
        // 球体メッシュを生成
        let mesh = MeshResource.generateSphere(radius: radius)
        
        // マテリアルを作成
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = MaterialScalarParameter(floatLiteral: 0.2)
        material.metallic = MaterialScalarParameter(floatLiteral: 0.3)
        
        // ModelEntityを作成
        let entity = ModelEntity(mesh: mesh, materials: [material])
        
        // コリジョン形状を設定
        entity.generateCollisionShapes(recursive: true)
        
        // 名前を設定
        entity.name = "TestSphere"
        
        print("テストスフィアを生成: 半径 \(radius)m")
        return entity
    }
    
    /// テスト用円柱モデルを生成
    /// - Parameters:
    ///   - height: 円柱の高さ（メートル）
    ///   - radius: 円柱の半径（メートル）
    ///   - color: 円柱の色
    /// - Returns: 生成されたModelEntity
    static func generateTestCylinder(height: Float = 0.8, radius: Float = 0.2, color: UIColor = .systemGreen) -> ModelEntity {
        // 円柱メッシュを生成
        let mesh = MeshResource.generateCylinder(height: height, radius: radius)
        
        // マテリアルを作成
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = MaterialScalarParameter(floatLiteral: 0.4)
        material.metallic = MaterialScalarParameter(floatLiteral: 0.0)
        
        // ModelEntityを作成
        let entity = ModelEntity(mesh: mesh, materials: [material])
        
        // コリジョン形状を設定
        entity.generateCollisionShapes(recursive: true)
        
        // 名前を設定
        entity.name = "TestCylinder"
        
        print("テスト円柱を生成: 高さ \(height)m, 半径 \(radius)m")
        return entity
    }
    
    /// テスト用平面モデルを生成
    /// - Parameters:
    ///   - width: 平面の幅（メートル）
    ///   - depth: 平面の奥行き（メートル）
    ///   - color: 平面の色
    /// - Returns: 生成されたModelEntity
    static func generateTestPlane(width: Float = 1.0, depth: Float = 1.0, color: UIColor = .systemYellow) -> ModelEntity {
        // 平面メッシュを生成
        let mesh = MeshResource.generatePlane(width: width, depth: depth)
        
        // マテリアルを作成
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = MaterialScalarParameter(floatLiteral: 0.8)
        material.metallic = MaterialScalarParameter(floatLiteral: 0.0)
        
        // ModelEntityを作成
        let entity = ModelEntity(mesh: mesh, materials: [material])
        
        // コリジョン形状を設定
        entity.generateCollisionShapes(recursive: true)
        
        // 名前を設定
        entity.name = "TestPlane"
        
        print("テスト平面を生成: \(width)m x \(depth)m")
        return entity
    }
    
    // MARK: - Composite Models
    
    /// 複合テストモデル（テーブル風）を生成
    /// - Returns: 生成されたModelEntity
    static func generateTestTable() -> ModelEntity {
        // テーブル天板
        let tableTop = generateTestPlane(width: 1.2, depth: 0.8, color: .systemBrown)
        tableTop.position.y = 0.375 // 高さ75cmの位置
        
        // テーブル脚（4本）
        let legHeight: Float = 0.75
        let legRadius: Float = 0.03
        let legPositions: [SIMD3<Float>] = [
            SIMD3<Float>(-0.5, legHeight/2, -0.35),  // 左奥
            SIMD3<Float>(0.5, legHeight/2, -0.35),   // 右奥
            SIMD3<Float>(-0.5, legHeight/2, 0.35),   // 左手前
            SIMD3<Float>(0.5, legHeight/2, 0.35)     // 右手前
        ]
        
        // 親エンティティを作成
        let tableEntity = Entity()
        tableEntity.name = "TestTable"
        
        // 天板を追加
        tableEntity.addChild(tableTop)
        
        // 脚を追加
        for (index, position) in legPositions.enumerated() {
            let leg = generateTestCylinder(height: legHeight, radius: legRadius, color: .systemBrown)
            leg.position = position
            leg.name = "TableLeg\(index + 1)"
            tableEntity.addChild(leg)
        }
        
        // ModelEntityに変換
        let modelEntity = ModelEntity()
        modelEntity.addChild(tableEntity)
        
        // 全体のコリジョン形状を設定
        modelEntity.generateCollisionShapes(recursive: true)
        
        print("テストテーブルを生成")
        return modelEntity
    }
    
    /// 複合テストモデル（椅子風）を生成
    /// - Returns: 生成されたModelEntity
    static func generateTestChair() -> ModelEntity {
        // 座面
        let seat = generateTestPlane(width: 0.5, depth: 0.5, color: .systemIndigo)
        seat.position.y = 0.225 // 高さ45cmの位置
        
        // 背もたれ
        let backrest = generateTestPlane(width: 0.5, depth: 0.05, color: .systemIndigo)
        backrest.position = SIMD3<Float>(0, 0.6, -0.225) // 座面の後ろ
        
        // 椅子脚（4本）
        let legHeight: Float = 0.45
        let legRadius: Float = 0.02
        let legPositions: [SIMD3<Float>] = [
            SIMD3<Float>(-0.2, legHeight/2, -0.2),   // 左奥
            SIMD3<Float>(0.2, legHeight/2, -0.2),    // 右奥
            SIMD3<Float>(-0.2, legHeight/2, 0.2),    // 左手前
            SIMD3<Float>(0.2, legHeight/2, 0.2)      // 右手前
        ]
        
        // 親エンティティを作成
        let chairEntity = Entity()
        chairEntity.name = "TestChair"
        
        // 座面と背もたれを追加
        chairEntity.addChild(seat)
        chairEntity.addChild(backrest)
        
        // 脚を追加
        for (index, position) in legPositions.enumerated() {
            let leg = generateTestCylinder(height: legHeight, radius: legRadius, color: .systemIndigo)
            leg.position = position
            leg.name = "ChairLeg\(index + 1)"
            chairEntity.addChild(leg)
        }
        
        // ModelEntityに変換
        let modelEntity = ModelEntity()
        modelEntity.addChild(chairEntity)
        
        // 全体のコリジョン形状を設定
        modelEntity.generateCollisionShapes(recursive: true)
        
        print("テストチェアを生成")
        return modelEntity
    }
    
    // MARK: - Model Factory
    
    /// 指定された家具モデルに対応するテストモデルを生成
    /// - Parameter furnitureModel: 家具モデル
    /// - Returns: 生成されたModelEntity、対応するモデルがない場合はnil
    static func generateModel(for furnitureModel: FurnitureModel) -> ModelEntity? {
        switch furnitureModel.id {
        case "test_cube_001":
            return generateTestCube(
                size: furnitureModel.realWorldSize.maxDimension,
                color: .systemBlue
            )
            
        case "test_sphere_001":
            return generateTestSphere(
                radius: furnitureModel.realWorldSize.maxDimension / 2,
                color: .systemRed
            )
            
        case "test_table_001":
            return generateTestTable()
            
        case "test_chair_001":
            return generateTestChair()
            
        default:
            print("警告: \(furnitureModel.id) に対応するテストモデルが見つかりません")
            // デフォルトとしてキューブを返す
            return generateTestCube(
                size: furnitureModel.realWorldSize.maxDimension,
                color: .systemGray
            )
        }
    }
    
    // MARK: - Material Utilities
    
    /// 指定された色でシンプルマテリアルを作成
    /// - Parameters:
    ///   - color: ベースカラー
    ///   - roughness: 粗さ（0.0-1.0）
    ///   - metallic: 金属性（0.0-1.0）
    /// - Returns: 作成されたSimpleMaterial
    static func createMaterial(color: UIColor, roughness: Float = 0.5, metallic: Float = 0.0) -> SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = MaterialScalarParameter(floatLiteral: roughness)
        material.metallic = MaterialScalarParameter(floatLiteral: metallic)
        return material
    }
    
    /// グラデーションマテリアルを作成
    /// - Parameters:
    ///   - startColor: 開始色
    ///   - endColor: 終了色
    /// - Returns: 作成されたSimpleMaterial
    static func createGradientMaterial(startColor: UIColor, endColor: UIColor) -> SimpleMaterial {
        var material = SimpleMaterial()
        // シンプルな実装として中間色を使用
        let startComponents = startColor.cgColor.components ?? [0, 0, 0, 1]
        let endComponents = endColor.cgColor.components ?? [0, 0, 0, 1]
        
        let midColor = UIColor(
            red: (startComponents[0] + endComponents[0]) / 2,
            green: (startComponents[1] + endComponents[1]) / 2,
            blue: (startComponents[2] + endComponents[2]) / 2,
            alpha: 1.0
        )
        material.color = .init(tint: midColor)
        material.roughness = MaterialScalarParameter(floatLiteral: 0.3)
        return material
    }
}