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
    let metadata: FurnitureMetadata?
    
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
        
        /// デフォルト寸法を作成
        static let defaultSize = RealWorldSize(width: 1.0, height: 1.0, depth: 1.0)
        
        /// 寸法の妥当性をチェック
        var isValid: Bool {
            return width > 0 && height > 0 && depth > 0 && 
                   width <= 10.0 && height <= 5.0 && depth <= 10.0 // 現実的な上限
        }
    }
    
    /// 家具メタデータを表す構造体
    struct FurnitureMetadata: Codable, Equatable {
        let description: String?
        let tags: [String]?
        let materialType: String?
        let weight: Float?
        let scalingStrategy: String?
        let accuracyLevel: String?
        
        /// スケーリング戦略を取得
        var preferredScalingStrategy: ScalingStrategy {
            guard let strategy = scalingStrategy else { return .uniform }
            
            switch strategy.lowercased() {
            case "uniform": return .uniform
            case "fittoLargestdimension": return .fitToLargestDimension
            case "fittovolume": return .fitToVolume
            case "averagedimensions": return .averageDimensions
            default: return .uniform
            }
        }
        
        /// 期待精度レベルを取得
        var expectedAccuracyLevel: AccuracyLevel {
            guard let level = accuracyLevel else { return .medium }
            
            switch level.lowercased() {
            case "high": return .high
            case "medium": return .medium
            case "low": return .low
            default: return .medium
            }
        }
        
        /// デフォルトメタデータを作成
        static let defaultMetadata = FurnitureMetadata(
            description: "家具モデル",
            tags: [],
            materialType: "不明",
            weight: 1.0,
            scalingStrategy: "uniform",
            accuracyLevel: "medium"
        )
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
    
    /// 3Dモデルを非同期で読み込み（自動スケール適用機能付き）
    /// - Returns: 読み込まれたModelEntity、失敗時はnil
    func loadModel() async -> ModelEntity? {
        print("🎯 モデル読み込み開始: \(name)")
        print("  カテゴリ: \(category.rawValue)")
        print("  ファイル名: \(modelFileName)")
        print("  タグ: \(metadata?.tags ?? [])")
        
        // 生成されたモデルかどうかチェック
        let isGeneratedModel = metadata?.tags?.contains("meshy-generated") ?? false ||
                              (modelFileName.contains("-") && modelFileName.hasSuffix(".usdz"))
        
        print("  生成モデル判定: \(isGeneratedModel)")
        
        if isGeneratedModel {
            // 生成されたモデルの場合、Documents ディレクトリから読み込み
            if let generatedEntity = await loadGeneratedModel() {
                return generatedEntity
            }
            print("生成モデルの読み込みに失敗、フォールバックを試行")
        }
        
        // テストカテゴリの場合は、プログラム生成モデルを使用
        if category == .test && !isGeneratedModel {
            return await MainActor.run {
                return loadTestModelWithAutoScale()
            }
        }
        
        // 通常のUSDZファイル読み込み（Bundleから）
        do {
            // USDZファイルを読み込み
            let entity = try await ModelEntity(named: modelFileName)
            
            // 自動スケール適用
            let scaleResult = await applyAutoScale(to: entity)
            
            // コリジョン形状を設定（タップ検出用）
            await entity.generateCollisionShapes(recursive: true)
            
            print("モデル読み込み成功: \(name)")
            print("スケール適用結果: \(scaleResult.report)")
            
            return entity
            
        } catch {
            print("モデル読み込み失敗: \(name) - \(error.localizedDescription)")
            
            // フォールバック: テストモデルを生成
            print("フォールバック: テストモデルを生成します")
            return await MainActor.run {
                return loadTestModelWithAutoScale()
            }
        }
    }
    
    /// 生成されたモデルを Documents ディレクトリから読み込み
    /// - Returns: 読み込まれたModelEntity、失敗時はnil
    private func loadGeneratedModel() async -> ModelEntity? {
        print("🔍 生成モデルの読み込みを開始: \(name)")
        print("🔍 モデルファイル名: \(modelFileName)")
        
        // Documents ディレクトリの GeneratedModels フォルダから読み込み
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Documents ディレクトリが見つかりません")
            return nil
        }
        
        let modelsDirectory = documentsDirectory.appendingPathComponent("GeneratedModels")
        let modelURL = modelsDirectory.appendingPathComponent(modelFileName)
        
        print("🔍 モデルファイルの完全パス: \(modelURL.path)")
        
        // ディレクトリの内容を確認（デバッグ用）
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
            print("🔍 GeneratedModels ディレクトリの内容: \(contents.map { $0.lastPathComponent })")
        } catch {
            print("⚠️ GeneratedModels ディレクトリの読み込みエラー: \(error)")
        }
        
        // ファイルの存在を確認
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            print("❌ 生成されたモデルファイルが存在しません: \(modelURL.path)")
            return nil
        }
        
        print("✅ モデルファイルが存在します")
        
        do {
            // モデルを読み込み
            let entity = try await ModelEntity(contentsOf: modelURL)
            
            // 自動スケール適用
            let scaleResult = await applyAutoScale(to: entity)
            
            // コリジョン形状を設定（タップ検出用）
            await entity.generateCollisionShapes(recursive: true)
            
            print("✅ 生成モデル読み込み成功: \(name) from \(modelURL.lastPathComponent)")
            print("📐 スケール適用結果: \(scaleResult.report)")
            
            return entity
            
        } catch {
            print("❌ 生成モデル読み込み失敗: \(name) - \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 自動スケール適用機能
    /// - Parameter entity: スケールを適用するModelEntity
    /// - Returns: スケール適用結果
    @MainActor
    private func applyAutoScale(to entity: ModelEntity) -> AutoScaleResult {
        // バウンディングボックスを計算
        guard let boundingBox = calculateBoundingBox(for: entity) else {
            print("警告: \(name) のバウンディングボックスを取得できません。デフォルトスケールを適用します。")
            entity.scale = SIMD3<Float>(repeating: defaultScale)
            return AutoScaleResult(
                appliedScale: defaultScale,
                strategy: .uniform,
                accuracyResult: nil,
                fallbackUsed: true,
                consistencyCheck: false
            )
        }
        
        // メタデータから推奨スケーリング戦略を取得
        let strategy = metadata?.preferredScalingStrategy ?? .uniform
        
        // スケール係数を計算
        let calculatedScale = calculateScaleFromRealWorldSize(
            modelSize: boundingBox.size,
            strategy: strategy
        )
        
        // スケール制限を適用
        let clampedScale = max(minScale, min(maxScale, calculatedScale))
        
        // スケールを適用
        entity.scale = SIMD3<Float>(repeating: clampedScale)
        
        // 精度検証
        let accuracyResult = verifyScaleAccuracy(
            appliedScale: clampedScale,
            modelSize: boundingBox.size
        )
        
        // 一貫性チェック
        let consistencyCheck = performConsistencyCheck(
            appliedScale: clampedScale,
            boundingBox: boundingBox
        )
        
        return AutoScaleResult(
            appliedScale: clampedScale,
            strategy: strategy,
            accuracyResult: accuracyResult,
            fallbackUsed: false,
            consistencyCheck: consistencyCheck
        )
    }
    
    /// テストモデルを読み込み（自動スケール適用機能付き）
    /// - Returns: 生成されたテストModelEntity
    @MainActor
    private func loadTestModelWithAutoScale() -> ModelEntity? {
        guard let entity = TestModelGenerator.generateModel(for: self) else {
            return nil
        }
        
        // 自動スケール適用
        let scaleResult = applyAutoScale(to: entity)
        
        print("テストモデル生成成功: \(name)")
        print("スケール適用結果: \(scaleResult.report)")
        
        return entity
    }
    
    /// 一貫性チェックを実行
    /// - Parameters:
    ///   - appliedScale: 適用されたスケール
    ///   - boundingBox: バウンディングボックス情報
    /// - Returns: 一貫性チェックの結果
    private func performConsistencyCheck(appliedScale: Float, boundingBox: BoundingBoxInfo) -> Bool {
        // スケール後のサイズを計算
        let scaledSize = SIMD3<Float>(
            abs(boundingBox.size.x) * appliedScale,
            abs(boundingBox.size.y) * appliedScale,
            abs(boundingBox.size.z) * appliedScale
        )
        
        // 現実的なサイズ範囲内かチェック
        let minReasonableSize: Float = 0.01 // 1cm
        let maxReasonableSize: Float = 10.0  // 10m
        
        let isWithinReasonableRange = 
            scaledSize.x >= minReasonableSize && scaledSize.x <= maxReasonableSize &&
            scaledSize.y >= minReasonableSize && scaledSize.y <= maxReasonableSize &&
            scaledSize.z >= minReasonableSize && scaledSize.z <= maxReasonableSize
        
        // カテゴリ別の妥当性チェック
        let isCategoryAppropriate = checkCategoryAppropriateSize(scaledSize: scaledSize)
        
        return isWithinReasonableRange && isCategoryAppropriate
    }
    
    /// カテゴリに適したサイズかチェック
    /// - Parameter scaledSize: スケール後のサイズ
    /// - Returns: カテゴリに適しているかどうか
    private func checkCategoryAppropriateSize(scaledSize: SIMD3<Float>) -> Bool {
        switch category {
        case .sofa:
            // ソファの一般的なサイズ範囲
            return scaledSize.x >= 1.0 && scaledSize.x <= 4.0 &&
                   scaledSize.y >= 0.3 && scaledSize.y <= 1.2 &&
                   scaledSize.z >= 0.5 && scaledSize.z <= 1.5
            
        case .table:
            // テーブルの一般的なサイズ範囲
            return scaledSize.x >= 0.5 && scaledSize.x <= 3.0 &&
                   scaledSize.y >= 0.5 && scaledSize.y <= 1.2 &&
                   scaledSize.z >= 0.5 && scaledSize.z <= 2.0
            
        case .chair:
            // 椅子の一般的なサイズ範囲
            return scaledSize.x >= 0.3 && scaledSize.x <= 1.0 &&
                   scaledSize.y >= 0.5 && scaledSize.y <= 1.5 &&
                   scaledSize.z >= 0.3 && scaledSize.z <= 1.0
            
        case .storage:
            // 収納家具の一般的なサイズ範囲
            return scaledSize.x >= 0.3 && scaledSize.x <= 3.0 &&
                   scaledSize.y >= 0.5 && scaledSize.y <= 3.0 &&
                   scaledSize.z >= 0.2 && scaledSize.z <= 1.0
            
        case .test:
            // テストモデルは制限を緩く
            return scaledSize.x >= 0.1 && scaledSize.x <= 5.0 &&
                   scaledSize.y >= 0.1 && scaledSize.y <= 5.0 &&
                   scaledSize.z >= 0.1 && scaledSize.z <= 5.0
        }
    }
    
    /// モデルの適切なスケールを計算（ARKitの1単位=1メートル標準に基づく）
    /// - Parameter entity: スケールを計算するModelEntity
    /// - Returns: 計算されたスケール値
    private func calculateScale(for entity: ModelEntity) -> Float {
        // モデルの現在のバウンディングボックスを取得
        let currentBounds = entity.model?.mesh.bounds
        
        guard let bounds = currentBounds else {
            print("警告: \(name) のバウンディングボックスを取得できません。デフォルトスケールを使用します。")
            return defaultScale
        }
        
        // 現在のサイズを計算（モデル座標系）
        let currentSize = bounds.max - bounds.min
        
        // 実世界サイズ（メートル単位）
        let targetSize = realWorldSize.simd
        
        // 各軸のスケール係数を計算
        let scaleX = targetSize.x / abs(currentSize.x)
        let scaleY = targetSize.y / abs(currentSize.y)
        let scaleZ = targetSize.z / abs(currentSize.z)
        
        // 統一スケールを使用（アスペクト比を保持）
        // 最小スケールを使用してモデルが目標サイズを超えないようにする
        let uniformScale = min(scaleX, min(scaleY, scaleZ))
        
        // スケール制限を適用
        let clampedScale = max(minScale, min(maxScale, uniformScale))
        
        // スケール精度の検証
        let scaledSize = SIMD3<Float>(
            abs(currentSize.x) * clampedScale,
            abs(currentSize.y) * clampedScale,
            abs(currentSize.z) * clampedScale
        )
        
        let sizeAccuracy = calculateSizeAccuracy(scaledSize: scaledSize, targetSize: targetSize)
        
        print("スケール計算: \(name)")
        print("  現在サイズ: \(currentSize)")
        print("  目標サイズ: \(targetSize)")
        print("  軸別スケール: X=\(scaleX), Y=\(scaleY), Z=\(scaleZ)")
        print("  統一スケール: \(uniformScale)")
        print("  適用スケール: \(clampedScale)")
        print("  スケール後サイズ: \(scaledSize)")
        print("  サイズ精度: \(String(format: "%.1f", sizeAccuracy * 100))%")
        
        return clampedScale
    }
    
    /// スケール後のサイズ精度を計算
    /// - Parameters:
    ///   - scaledSize: スケール適用後のサイズ
    ///   - targetSize: 目標サイズ
    /// - Returns: 精度（0.0-1.0）
    private func calculateSizeAccuracy(scaledSize: SIMD3<Float>, targetSize: SIMD3<Float>) -> Float {
        let accuracyX = 1.0 - abs(scaledSize.x - targetSize.x) / targetSize.x
        let accuracyY = 1.0 - abs(scaledSize.y - targetSize.y) / targetSize.y
        let accuracyZ = 1.0 - abs(scaledSize.z - targetSize.z) / targetSize.z
        
        return (accuracyX + accuracyY + accuracyZ) / 3.0
    }
    

    
    // MARK: - Scale Calculation System
    
    /// バウンディングボックスを計算（ARKit座標系）
    /// - Parameter entity: 計算対象のModelEntity
    /// - Returns: バウンディングボックス情報
    func calculateBoundingBox(for entity: ModelEntity) -> BoundingBoxInfo? {
        guard let bounds = entity.model?.mesh.bounds else {
            return nil
        }
        
        let size = bounds.max - bounds.min
        let center = (bounds.max + bounds.min) / 2
        
        return BoundingBoxInfo(
            size: size,
            center: center,
            min: bounds.min,
            max: bounds.max,
            volume: abs(size.x * size.y * size.z)
        )
    }
    
    /// 実寸法からスケール係数への変換（ARKitの1単位=1メートル標準）
    /// - Parameters:
    ///   - modelSize: モデルの現在サイズ
    ///   - strategy: スケーリング戦略
    /// - Returns: 計算されたスケール係数
    func calculateScaleFromRealWorldSize(modelSize: SIMD3<Float>, strategy: ScalingStrategy = .uniform) -> Float {
        let targetSize = realWorldSize.simd
        
        switch strategy {
        case .uniform:
            // 統一スケール（アスペクト比保持）
            let scaleX = targetSize.x / abs(modelSize.x)
            let scaleY = targetSize.y / abs(modelSize.y)
            let scaleZ = targetSize.z / abs(modelSize.z)
            return min(scaleX, min(scaleY, scaleZ))
            
        case .fitToLargestDimension:
            // 最大寸法に合わせる
            let currentMaxDimension = max(abs(modelSize.x), max(abs(modelSize.y), abs(modelSize.z)))
            let targetMaxDimension = realWorldSize.maxDimension
            return targetMaxDimension / currentMaxDimension
            
        case .fitToVolume:
            // 体積ベースのスケーリング
            let currentVolume = abs(modelSize.x * modelSize.y * modelSize.z)
            let targetVolume = realWorldSize.volume
            return pow(targetVolume / currentVolume, 1.0/3.0)
            
        case .averageDimensions:
            // 平均寸法ベース
            let currentAvg = (abs(modelSize.x) + abs(modelSize.y) + abs(modelSize.z)) / 3.0
            let targetAvg = (targetSize.x + targetSize.y + targetSize.z) / 3.0
            return targetAvg / currentAvg
        }
    }
    
    /// スケール精度を検証
    /// - Parameters:
    ///   - appliedScale: 適用されたスケール
    ///   - modelSize: モデルの元サイズ
    /// - Returns: 精度検証結果
    func verifyScaleAccuracy(appliedScale: Float, modelSize: SIMD3<Float>) -> ScaleAccuracyResult {
        let scaledSize = SIMD3<Float>(
            abs(modelSize.x) * appliedScale,
            abs(modelSize.y) * appliedScale,
            abs(modelSize.z) * appliedScale
        )
        
        let targetSize = realWorldSize.simd
        
        // 各軸の誤差を計算
        let errorX = abs(scaledSize.x - targetSize.x) / targetSize.x
        let errorY = abs(scaledSize.y - targetSize.y) / targetSize.y
        let errorZ = abs(scaledSize.z - targetSize.z) / targetSize.z
        
        let maxError = max(errorX, max(errorY, errorZ))
        let avgError = (errorX + errorY + errorZ) / 3.0
        
        // 精度レベルを判定
        let accuracyLevel: AccuracyLevel
        if maxError < 0.05 { // 5%未満
            accuracyLevel = .high
        } else if maxError < 0.15 { // 15%未満
            accuracyLevel = .medium
        } else {
            accuracyLevel = .low
        }
        
        return ScaleAccuracyResult(
            scaledSize: scaledSize,
            targetSize: targetSize,
            errorX: errorX,
            errorY: errorY,
            errorZ: errorZ,
            maxError: maxError,
            averageError: avgError,
            accuracyLevel: accuracyLevel
        )
    }
    
    // MARK: - Cross-Model Consistency
    
    /// 異なるサイズモデル間での一貫性を確保
    /// - Parameter otherModels: 比較対象の他のモデル
    /// - Returns: 一貫性チェック結果
    func ensureConsistencyWithOtherModels(_ otherModels: [FurnitureModel]) -> ConsistencyCheckResult {
        let issues: [String] = []
        var warnings: [String] = []
        
        // 同じカテゴリのモデルとの比較
        let sameCategory = otherModels.filter { $0.category == self.category }
        
        for otherModel in sameCategory {
            // スケール設定の一貫性チェック
            let scaleRatio = self.defaultScale / otherModel.defaultScale
            if scaleRatio > 2.0 || scaleRatio < 0.5 {
                warnings.append("モデル \(otherModel.name) とのスケール設定に大きな差があります")
            }
            
            // サイズ比率の妥当性チェック
            let sizeRatio = self.realWorldSize.volume / otherModel.realWorldSize.volume
            if sizeRatio > 10.0 || sizeRatio < 0.1 {
                warnings.append("モデル \(otherModel.name) とのサイズ比率が極端です")
            }
        }
        
        // メタデータの一貫性チェック
        let allModelsWithMetadata = otherModels.compactMap { $0.metadata }
        if let myMetadata = self.metadata {
            let strategyCounts = allModelsWithMetadata.reduce(into: [String: Int]()) { counts, metadata in
                if let strategy = metadata.scalingStrategy {
                    counts[strategy, default: 0] += 1
                }
            }
            
            if let myStrategy = myMetadata.scalingStrategy,
               let mostCommonStrategy = strategyCounts.max(by: { $0.value < $1.value })?.key,
               myStrategy != mostCommonStrategy {
                warnings.append("スケーリング戦略が他のモデルと異なります（推奨: \(mostCommonStrategy)）")
            }
        }
        
        return ConsistencyCheckResult(
            isConsistent: issues.isEmpty,
            issues: issues,
            warnings: warnings
        )
    }
    
    /// 複数モデルでの統一スケール基準を計算
    /// - Parameter models: 対象モデル群
    /// - Returns: 統一スケール基準
    static func calculateUnifiedScaleStandard(for models: [FurnitureModel]) -> UnifiedScaleStandard {
        guard !models.isEmpty else {
            return UnifiedScaleStandard(
                baseScale: 1.0,
                scaleRange: (min: 0.5, max: 2.0),
                recommendedStrategy: .uniform
            )
        }
        
        // 各カテゴリの代表的なサイズを計算
        let categoryAverages = Dictionary(grouping: models, by: { $0.category })
            .mapValues { categoryModels in
                let totalVolume = categoryModels.reduce(0) { $0 + $1.realWorldSize.volume }
                return totalVolume / Float(categoryModels.count)
            }
        
        // 基準スケールを計算（最も一般的なカテゴリのサイズを基準）
        let baseVolume = categoryAverages.values.sorted()[categoryAverages.count / 2] // 中央値
        let baseScale = pow(baseVolume, 1.0/3.0) // 立方根でスケールを算出
        
        // スケール範囲を計算
        let allScales = models.map { $0.defaultScale }
        let minScale = allScales.min() ?? 0.5
        let maxScale = allScales.max() ?? 2.0
        
        // 推奨戦略を決定（最も多く使われている戦略）
        let strategyCounts = models.compactMap { $0.metadata?.scalingStrategy }
            .reduce(into: [String: Int]()) { counts, strategy in
                counts[strategy, default: 0] += 1
            }
        
        let recommendedStrategyString = strategyCounts.max(by: { $0.value < $1.value })?.key ?? "uniform"
        let recommendedStrategy: ScalingStrategy
        switch recommendedStrategyString.lowercased() {
        case "uniform": recommendedStrategy = .uniform
        case "fittoLargestdimension": recommendedStrategy = .fitToLargestDimension
        case "fittovolume": recommendedStrategy = .fitToVolume
        case "averagedimensions": recommendedStrategy = .averageDimensions
        default: recommendedStrategy = .uniform
        }
        
        return UnifiedScaleStandard(
            baseScale: baseScale,
            scaleRange: (min: minScale, max: maxScale),
            recommendedStrategy: recommendedStrategy
        )
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
            minScale: 0.5,
            metadata: FurnitureMetadata(
                description: "基本的な立方体モデル（テスト用）",
                tags: ["テスト", "基本形状", "立方体"],
                materialType: "プラスチック",
                weight: 1.0,
                scalingStrategy: "uniform",
                accuracyLevel: "high"
            )
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
            minScale: 0.5,
            metadata: FurnitureMetadata(
                description: "基本的な球体モデル（テスト用）",
                tags: ["テスト", "基本形状", "球体"],
                materialType: "プラスチック",
                weight: 0.8,
                scalingStrategy: "uniform",
                accuracyLevel: "high"
            )
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
            minScale: 0.7,
            metadata: FurnitureMetadata(
                description: "シンプルなテーブルモデル（テスト用）",
                tags: ["テスト", "テーブル", "家具"],
                materialType: "木材",
                weight: 15.0,
                scalingStrategy: "uniform",
                accuracyLevel: "medium"
            )
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
            minScale: 0.8,
            metadata: FurnitureMetadata(
                description: "シンプルな椅子モデル（テスト用）",
                tags: ["テスト", "椅子", "家具"],
                materialType: "木材",
                weight: 8.0,
                scalingStrategy: "uniform",
                accuracyLevel: "medium"
            )
        )
    ]
}

// MARK: - Supporting Types for Scale Calculation

/// バウンディングボックス情報
struct BoundingBoxInfo {
    let size: SIMD3<Float>
    let center: SIMD3<Float>
    let min: SIMD3<Float>
    let max: SIMD3<Float>
    let volume: Float
    
    /// 最大寸法を取得
    var maxDimension: Float {
        return Swift.max(abs(size.x), Swift.max(abs(size.y), abs(size.z)))
    }
    
    /// 最小寸法を取得
    var minDimension: Float {
        return Swift.min(abs(size.x), Swift.min(abs(size.y), abs(size.z)))
    }
    
    /// アスペクト比を計算
    var aspectRatio: SIMD3<Float> {
        let maxDim = maxDimension
        return SIMD3<Float>(
            abs(size.x) / maxDim,
            abs(size.y) / maxDim,
            abs(size.z) / maxDim
        )
    }
}

/// スケーリング戦略
enum ScalingStrategy {
    case uniform                    // 統一スケール（アスペクト比保持）
    case fitToLargestDimension     // 最大寸法に合わせる
    case fitToVolume               // 体積ベース
    case averageDimensions         // 平均寸法ベース
}

/// 精度レベル
enum AccuracyLevel {
    case high    // 高精度（誤差5%未満）
    case medium  // 中精度（誤差15%未満）
    case low     // 低精度（誤差15%以上）
    
    var description: String {
        switch self {
        case .high: return "高精度"
        case .medium: return "中精度"
        case .low: return "低精度"
        }
    }
}

/// スケール精度検証結果
struct ScaleAccuracyResult {
    let scaledSize: SIMD3<Float>
    let targetSize: SIMD3<Float>
    let errorX: Float
    let errorY: Float
    let errorZ: Float
    let maxError: Float
    let averageError: Float
    let accuracyLevel: AccuracyLevel
    
    /// 精度が許容範囲内かどうか
    var isAcceptable: Bool {
        return accuracyLevel != .low
    }
    
    /// 精度レポートを生成
    var report: String {
        return """
        スケール精度レポート:
        - 目標サイズ: \(targetSize)
        - 実際サイズ: \(scaledSize)
        - 誤差: X=\(String(format: "%.1f", errorX * 100))%, Y=\(String(format: "%.1f", errorY * 100))%, Z=\(String(format: "%.1f", errorZ * 100))%
        - 最大誤差: \(String(format: "%.1f", maxError * 100))%
        - 平均誤差: \(String(format: "%.1f", averageError * 100))%
        - 精度レベル: \(accuracyLevel.description)
        """
    }
}

/// 自動スケール適用結果
struct AutoScaleResult {
    let appliedScale: Float
    let strategy: ScalingStrategy
    let accuracyResult: ScaleAccuracyResult?
    let fallbackUsed: Bool
    let consistencyCheck: Bool
    
    /// 適用が成功したかどうか
    var isSuccessful: Bool {
        return !fallbackUsed && consistencyCheck && (accuracyResult?.isAcceptable ?? false)
    }
    
    /// 結果レポートを生成
    var report: String {
        var report = """
        自動スケール適用結果:
        - 適用スケール: \(appliedScale)
        - 戦略: \(strategy)
        - フォールバック使用: \(fallbackUsed ? "はい" : "いいえ")
        - 一貫性チェック: \(consistencyCheck ? "合格" : "不合格")
        """
        
        if let accuracyResult = accuracyResult {
            report += "\n- 精度: \(accuracyResult.accuracyLevel.description)"
            report += "\n- 最大誤差: \(String(format: "%.1f", accuracyResult.maxError * 100))%"
        }
        
        if isSuccessful {
            report += "\n✅ スケール適用成功"
        } else {
            report += "\n⚠️ スケール適用に問題があります"
        }
        
        return report
    }
}

/// 一貫性チェック結果
struct ConsistencyCheckResult {
    let isConsistent: Bool
    let issues: [String]
    let warnings: [String]
    
    /// 一貫性レポートを生成
    var report: String {
        var report = "一貫性チェック結果:\n"
        
        if isConsistent {
            report += "✅ 一貫性チェック合格\n"
        } else {
            report += "❌ 一貫性チェック不合格\n"
            for issue in issues {
                report += "  - \(issue)\n"
            }
        }
        
        if !warnings.isEmpty {
            report += "⚠️ 警告:\n"
            for warning in warnings {
                report += "  - \(warning)\n"
            }
        }
        
        return report
    }
}

/// 統一スケール基準
struct UnifiedScaleStandard {
    let baseScale: Float
    let scaleRange: (min: Float, max: Float)
    let recommendedStrategy: ScalingStrategy
    
    /// 基準レポートを生成
    var report: String {
        return """
        統一スケール基準:
        - 基準スケール: \(baseScale)
        - スケール範囲: \(scaleRange.min) - \(scaleRange.max)
        - 推奨戦略: \(recommendedStrategy)
        """
    }
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