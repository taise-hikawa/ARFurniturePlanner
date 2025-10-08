//
//  FurnitureModel.swift
//  ARFurniturePlanner
//
//  Created by Kiro on 2025/10/09.
//

import Foundation
import RealityKit
import simd

/// 家具カテゴリの列挙型
enum FurnitureCategory: String, CaseIterable, Codable {
    case sofa = "ソファ"
    case table = "テーブル"
    case chair = "椅子"
    case storage = "収納"
    case test = "テスト"
    
    var displayName: String {
        return self.rawValue
    }
}

/// 家具の3Dモデルとメタデータを管理する構造体
struct FurnitureModel: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let category: FurnitureCategory
    let modelFileName: String
    let thumbnailFileName: String?
    let realWorldSize: RealWorldSize
    let defaultScale: Float
    let maxScale: Float
    let minScale: Float
    
    /// 実世界サイズを表す構造体
    struct RealWorldSize: Codable, Equatable {
        let width: Float   // 幅（メートル）
        let height: Float  // 高さ（メートル）
        let depth: Float   // 奥行き（メートル）
        
        /// SIMD3<Float>に変換
        var simd: SIMD3<Float> {
            return SIMD3<Float>(width, height, depth)
        }
        
        /// 体積を計算
        var volume: Float {
            return width * height * depth
        }
        
        /// 最大寸法を取得
        var maxDimension: Float {
            return max(width, max(height, depth))
        }
    }
    
    // MARK: - Computed Properties
    
    /// モデルファイルのフルパス
    var modelFilePath: String {
        return "Models/\(modelFileName)"
    }
    
    /// サムネイル画像のフルパス
    var thumbnailFilePath: String? {
        guard let thumbnailFileName = thumbnailFileName else { return nil }
        return "Thumbnails/\(thumbnailFileName)"
    }
    
    /// バウンディングボックスのサイズ
    var boundingBoxSize: SIMD3<Float> {
        return realWorldSize.simd
    }
    
    // MARK: - Model Loading
    
    /// 3Dモデルを非同期で読み込み
    /// - Returns: 読み込まれたModelEntity、失敗時はnil
    func loadModel() async -> ModelEntity? {
        // テストカテゴリの場合は、プログラム生成モデルを使用
        if category == .test {
            return loadTestModel()
        }
        
        // 通常のUSDZファイル読み込み
        do {
            // USDZファイルを読み込み
            let entity = try await ModelEntity(named: modelFileName)
            
            // 実世界サイズに基づいてスケールを適用
            let calculatedScale = calculateScale(for: entity)
            await MainActor.run {
                entity.scale = SIMD3<Float>(repeating: calculatedScale)
            }
            
            // コリジョン形状を設定（タップ検出用）
            await entity.generateCollisionShapes(recursive: true)
            
            print("モデル読み込み成功: \(name) (スケール: \(calculatedScale))")
            return entity
            
        } catch {
            print("モデル読み込み失敗: \(name) - \(error.localizedDescription)")
            
            // フォールバック: テストモデルを生成
            print("フォールバック: テストモデルを生成します")
            return loadTestModel()
        }
    }
    
    /// テストモデルを読み込み
    /// - Returns: 生成されたテストModelEntity
    private func loadTestModel() -> ModelEntity? {
        let entity = TestModelGenerator.generateModel(for: self)
        
        if let entity = entity {
            // 実世界サイズに基づいてスケールを適用
            let calculatedScale = calculateTestModelScale(for: entity)
            entity.scale = SIMD3<Float>(repeating: calculatedScale)
            
            print("テストモデル生成成功: \(name) (スケール: \(calculatedScale))")
        }
        
        return entity
    }
    
    /// モデルの適切なスケールを計算
    /// - Parameter entity: スケールを計算するModelEntity
    /// - Returns: 計算されたスケール値
    private func calculateScale(for entity: ModelEntity) -> Float {
        // モデルの現在のバウンディングボックスを取得
        let currentBounds = entity.model?.mesh.bounds
        
        guard let bounds = currentBounds else {
            print("警告: \(name) のバウンディングボックスを取得できません。デフォルトスケールを使用します。")
            return defaultScale
        }
        
        // 現在のサイズを計算
        let currentSize = bounds.max - bounds.min
        let currentMaxDimension = max(currentSize.x, max(currentSize.y, currentSize.z))
        
        // 実世界サイズの最大寸法
        let targetMaxDimension = realWorldSize.maxDimension
        
        // スケール係数を計算（ARKitの1単位=1メートル標準）
        let calculatedScale = targetMaxDimension / currentMaxDimension
        
        // スケール制限を適用
        let clampedScale = max(minScale, min(maxScale, calculatedScale))
        
        print("スケール計算: \(name)")
        print("  現在サイズ: \(currentSize)")
        print("  目標サイズ: \(realWorldSize.simd)")
        print("  計算スケール: \(calculatedScale)")
        print("  適用スケール: \(clampedScale)")
        
        return clampedScale
    }
    
    /// テストモデルの適切なスケールを計算
    /// - Parameter entity: スケールを計算するModelEntity
    /// - Returns: 計算されたスケール値
    private func calculateTestModelScale(for entity: ModelEntity) -> Float {
        // テストモデルは既に適切なサイズで生成されているため、
        // 基本的にはdefaultScaleを使用
        let calculatedScale = defaultScale
        
        // スケール制限を適用
        let clampedScale = max(minScale, min(maxScale, calculatedScale))
        
        print("テストモデルスケール計算: \(name)")
        print("  目標サイズ: \(realWorldSize.simd)")
        print("  適用スケール: \(clampedScale)")
        
        return clampedScale
    }
    
    // MARK: - Validation
    
    /// モデルデータの妥当性を検証
    /// - Returns: 妥当性チェックの結果
    func validate() -> ValidationResult {
        var issues: [String] = []
        
        // 必須フィールドのチェック
        if id.isEmpty {
            issues.append("IDが空です")
        }
        
        if name.isEmpty {
            issues.append("名前が空です")
        }
        
        if modelFileName.isEmpty {
            issues.append("モデルファイル名が空です")
        }
        
        // サイズの妥当性チェック
        if realWorldSize.width <= 0 || realWorldSize.height <= 0 || realWorldSize.depth <= 0 {
            issues.append("実世界サイズが無効です")
        }
        
        // スケールの妥当性チェック
        if defaultScale <= 0 {
            issues.append("デフォルトスケールが無効です")
        }
        
        if minScale >= maxScale {
            issues.append("最小スケールが最大スケール以上です")
        }
        
        return ValidationResult(isValid: issues.isEmpty, issues: issues)
    }
    
    /// バリデーション結果
    struct ValidationResult {
        let isValid: Bool
        let issues: [String]
    }
}

// MARK: - Sample Data
extension FurnitureModel {
    /// テスト用のサンプル家具データ
    static let sampleModels: [FurnitureModel] = [
        FurnitureModel(
            id: "test_cube_001",
            name: "テストキューブ",
            category: .test,
            modelFileName: "test_cube.usdz",
            thumbnailFileName: "test_cube_thumb.jpg",
            realWorldSize: RealWorldSize(width: 0.5, height: 0.5, depth: 0.5),
            defaultScale: 1.0,
            maxScale: 2.0,
            minScale: 0.5
        ),
        FurnitureModel(
            id: "test_sphere_001",
            name: "テストスフィア",
            category: .test,
            modelFileName: "test_sphere.usdz",
            thumbnailFileName: "test_sphere_thumb.jpg",
            realWorldSize: RealWorldSize(width: 0.6, height: 0.6, depth: 0.6),
            defaultScale: 1.0,
            maxScale: 2.0,
            minScale: 0.5
        ),
        FurnitureModel(
            id: "test_table_001",
            name: "テストテーブル",
            category: .test,
            modelFileName: "test_table.usdz",
            thumbnailFileName: "test_table_thumb.jpg",
            realWorldSize: RealWorldSize(width: 1.2, height: 0.75, depth: 0.8),
            defaultScale: 1.0,
            maxScale: 1.5,
            minScale: 0.7
        ),
        FurnitureModel(
            id: "test_chair_001",
            name: "テストチェア",
            category: .test,
            modelFileName: "test_chair.usdz",
            thumbnailFileName: "test_chair_thumb.jpg",
            realWorldSize: RealWorldSize(width: 0.5, height: 0.9, depth: 0.5),
            defaultScale: 1.0,
            maxScale: 1.3,
            minScale: 0.8
        )
    ]
}

// MARK: - Error Types
enum FurnitureModelError: LocalizedError {
    case modelNotFound(String)
    case invalidModelFile(String)
    case scalingFailed(String)
    case validationFailed([String])
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound(let fileName):
            return "モデルファイルが見つかりません: \(fileName)"
        case .invalidModelFile(let fileName):
            return "無効なモデルファイルです: \(fileName)"
        case .scalingFailed(let modelName):
            return "モデルのスケーリングに失敗しました: \(modelName)"
        case .validationFailed(let issues):
            return "バリデーションエラー: \(issues.joined(separator: ", "))"
        }
    }
}