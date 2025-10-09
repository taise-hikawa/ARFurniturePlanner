//
//  FurnitureRepository.swift
//  ARFurniturePlanner
//
//  Created by Kiro on 2025/10/09.
//

import Foundation
import RealityKit
import Combine

/// 家具データの管理とキャッシングを行うクラス
@MainActor
class FurnitureRepository: ObservableObject {
    
    // MARK: - Published Properties
    @Published var availableFurniture: [FurnitureModel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var modelCache: [String: ModelEntity] = [:]
    private let maxCacheSize = 10 // 最大キャッシュサイズ
    private var cacheAccessOrder: [String] = [] // LRU管理用
    private var databaseMetadata: FurnitureDatabase.DatabaseMetadata?
    
    // MARK: - Initialization
    init() {
        Task {
            await loadFurnitureDatabase()
        }
    }
    
    // MARK: - Data Loading
    
    /// 家具データベースを読み込み
    func loadFurnitureDatabase() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let (furnitureData, metadata) = try await loadFurnitureFromJSON()
            self.databaseMetadata = metadata
            
            // バリデーションを実行し、必要に応じてデフォルト値を適用
            let validatedFurniture = furnitureData.compactMap { furniture -> FurnitureModel? in
                let correctedFurniture = applyDefaultsIfNeeded(to: furniture)
                let validation = correctedFurniture.validate()
                
                if !validation.isValid {
                    print("警告: 家具データが無効です - \(correctedFurniture.name): \(validation.issues.joined(separator: ", "))")
                    // 重要でないエラーの場合は修正を試行
                    if let fixedFurniture = attemptToFixFurniture(correctedFurniture, issues: validation.issues) {
                        print("修正済み: \(fixedFurniture.name)")
                        return fixedFurniture
                    }
                    return nil
                }
                return correctedFurniture
            }
            
            availableFurniture = validatedFurniture
            print("家具データベース読み込み完了: \(availableFurniture.count)個のアイテム")
            
            if let metadata = databaseMetadata {
                print("データベースメタデータ読み込み完了")
                print("  バージョン: \(metadata.description ?? "不明")")
                print("  サポートカテゴリ: \(metadata.supportedCategories?.joined(separator: ", ") ?? "不明")")
            }
            
        } catch {
            errorMessage = "家具データベースの読み込みに失敗しました: \(error.localizedDescription)"
            print("エラー: \(error)")
            
            // フォールバック: サンプルデータを使用
            availableFurniture = FurnitureModel.sampleModels
            print("フォールバック: サンプルデータを使用します")
        }
        
        isLoading = false
    }
    
    /// JSONファイルから家具データを読み込み
    private func loadFurnitureFromJSON() async throws -> ([FurnitureModel], FurnitureDatabase.DatabaseMetadata?) {
        guard let url = Bundle.main.url(forResource: "furniture_metadata", withExtension: "json") else {
            throw FurnitureRepositoryError.metadataFileNotFound
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        
        do {
            let furnitureDatabase = try decoder.decode(FurnitureDatabase.self, from: data)
            return (furnitureDatabase.furniture, furnitureDatabase.metadata)
        } catch {
            print("JSONデコードエラー: \(error)")
            throw FurnitureRepositoryError.invalidJSONFormat
        }
    }
    
    /// 家具データにデフォルト値を適用（必要に応じて）
    private func applyDefaultsIfNeeded(to furniture: FurnitureModel) -> FurnitureModel {
        var correctedFurniture = furniture
        
        // 実世界サイズが無効な場合、デフォルト値を適用
        if !furniture.realWorldSize.isValid {
            let defaultSize = databaseMetadata?.defaultDimensions?.realWorldSize ?? 
                             FurnitureModel.RealWorldSize.defaultSize
            
            print("警告: \(furniture.name) の実世界サイズが無効です。デフォルト値を適用します: \(defaultSize.simd)")
            
            // 新しいFurnitureModelを作成（structなので直接変更できない）
            correctedFurniture = FurnitureModel(
                id: furniture.id,
                name: furniture.name,
                category: furniture.category,
                modelFileName: furniture.modelFileName,
                thumbnailFileName: furniture.thumbnailFileName,
                realWorldSize: defaultSize,
                defaultScale: furniture.defaultScale,
                maxScale: furniture.maxScale,
                minScale: furniture.minScale,
                metadata: furniture.metadata
            )
        }
        
        // メタデータが欠落している場合、デフォルトメタデータを適用
        if correctedFurniture.metadata == nil {
            print("警告: \(furniture.name) のメタデータが欠落しています。デフォルト値を適用します。")
            
            correctedFurniture = FurnitureModel(
                id: correctedFurniture.id,
                name: correctedFurniture.name,
                category: correctedFurniture.category,
                modelFileName: correctedFurniture.modelFileName,
                thumbnailFileName: correctedFurniture.thumbnailFileName,
                realWorldSize: correctedFurniture.realWorldSize,
                defaultScale: correctedFurniture.defaultScale,
                maxScale: correctedFurniture.maxScale,
                minScale: correctedFurniture.minScale,
                metadata: FurnitureModel.FurnitureMetadata.defaultMetadata
            )
        }
        
        return correctedFurniture
    }
    
    /// 家具データの修正を試行
    private func attemptToFixFurniture(_ furniture: FurnitureModel, issues: [String]) -> FurnitureModel? {
        var fixedFurniture = furniture
        var canFix = true
        
        for issue in issues {
            switch issue {
            case let issue where issue.contains("実世界サイズが無効"):
                // デフォルトサイズを適用
                let defaultSize = databaseMetadata?.defaultDimensions?.realWorldSize ?? 
                                 FurnitureModel.RealWorldSize.defaultSize
                fixedFurniture = FurnitureModel(
                    id: fixedFurniture.id,
                    name: fixedFurniture.name,
                    category: fixedFurniture.category,
                    modelFileName: fixedFurniture.modelFileName,
                    thumbnailFileName: fixedFurniture.thumbnailFileName,
                    realWorldSize: defaultSize,
                    defaultScale: fixedFurniture.defaultScale,
                    maxScale: fixedFurniture.maxScale,
                    minScale: fixedFurniture.minScale,
                    metadata: fixedFurniture.metadata
                )
                
            case let issue where issue.contains("デフォルトスケールが無効"):
                // デフォルトスケーリング設定を適用
                let defaultScaling = databaseMetadata?.defaultScaling
                fixedFurniture = FurnitureModel(
                    id: fixedFurniture.id,
                    name: fixedFurniture.name,
                    category: fixedFurniture.category,
                    modelFileName: fixedFurniture.modelFileName,
                    thumbnailFileName: fixedFurniture.thumbnailFileName,
                    realWorldSize: fixedFurniture.realWorldSize,
                    defaultScale: defaultScaling?.defaultScale ?? 1.0,
                    maxScale: defaultScaling?.maxScale ?? 2.0,
                    minScale: defaultScaling?.minScale ?? 0.5,
                    metadata: fixedFurniture.metadata
                )
                
            default:
                // 修正できない問題
                canFix = false
                break
            }
        }
        
        return canFix ? fixedFurniture : nil
    }
    
    // MARK: - Model Loading and Caching
    
    /// 指定された家具モデルを読み込み（キャッシュ機能付き）
    /// - Parameter model: 読み込む家具モデル
    /// - Returns: 読み込まれたModelEntity、失敗時はnil
    func loadModel(_ model: FurnitureModel) async -> ModelEntity? {
        // キャッシュから検索
        if let cachedEntity = getCachedModel(for: model) {
            print("キャッシュからモデルを取得: \(model.name)")
            updateCacheAccess(for: model.id)
            return cachedEntity.clone(recursive: true)
        }
        
        // モデルを新規読み込み
        print("モデルを新規読み込み: \(model.name)")
        guard let entity = await model.loadModel() else {
            return nil
        }
        
        // キャッシュに保存
        cacheModel(entity, for: model)
        
        // 新しいインスタンスを返す（元のキャッシュを保護）
        return entity.clone(recursive: true)
    }
    
    /// モデルをキャッシュに保存
    /// - Parameters:
    ///   - entity: キャッシュするModelEntity
    ///   - model: 対応する家具モデル
    func cacheModel(_ entity: ModelEntity, for model: FurnitureModel) {
        // キャッシュサイズ制限チェック
        if modelCache.count >= maxCacheSize {
            evictLeastRecentlyUsed()
        }
        
        // キャッシュに保存
        modelCache[model.id] = entity
        updateCacheAccess(for: model.id)
        
        print("モデルをキャッシュに保存: \(model.name) (キャッシュサイズ: \(modelCache.count))")
    }
    
    /// キャッシュからモデルを取得
    /// - Parameter model: 取得する家具モデル
    /// - Returns: キャッシュされたModelEntity、存在しない場合はnil
    func getCachedModel(for model: FurnitureModel) -> ModelEntity? {
        return modelCache[model.id]
    }
    
    /// キャッシュアクセス順序を更新（LRU管理）
    private func updateCacheAccess(for modelId: String) {
        // 既存のエントリを削除
        cacheAccessOrder.removeAll { $0 == modelId }
        // 最新として追加
        cacheAccessOrder.append(modelId)
    }
    
    /// 最も古いキャッシュエントリを削除
    private func evictLeastRecentlyUsed() {
        guard let oldestId = cacheAccessOrder.first else { return }
        
        modelCache.removeValue(forKey: oldestId)
        cacheAccessOrder.removeFirst()
        
        print("LRU: 古いキャッシュを削除: \(oldestId)")
    }
    
    /// キャッシュをクリア
    func clearCache() {
        modelCache.removeAll()
        cacheAccessOrder.removeAll()
        print("モデルキャッシュをクリアしました")
    }
    
    /// 未使用のキャッシュをクリア（パフォーマンス最適化用）
    func clearUnusedCache() {
        let halfCacheSize = maxCacheSize / 2
        
        // キャッシュサイズが半分以下の場合は何もしない
        if modelCache.count <= halfCacheSize {
            return
        }
        
        // 古いエントリから削除
        let removeCount = modelCache.count - halfCacheSize
        for _ in 0..<removeCount {
            evictLeastRecentlyUsed()
        }
        
        print("未使用キャッシュをクリア: \(removeCount)個のエントリを削除")
    }
    
    // MARK: - Furniture Filtering and Search
    
    /// カテゴリ別に家具を取得
    /// - Parameter category: 家具カテゴリ
    /// - Returns: 指定されたカテゴリの家具配列
    func getFurniture(by category: FurnitureCategory) -> [FurnitureModel] {
        return availableFurniture.filter { $0.category == category }
    }
    
    /// IDで家具を検索
    /// - Parameter id: 家具ID
    /// - Returns: 見つかった家具、存在しない場合はnil
    func getFurniture(by id: String) -> FurnitureModel? {
        return availableFurniture.first { $0.id == id }
    }
    
    /// 名前で家具を検索
    /// - Parameter name: 家具名（部分一致）
    /// - Returns: マッチした家具の配列
    func searchFurniture(by name: String) -> [FurnitureModel] {
        let lowercaseName = name.lowercased()
        return availableFurniture.filter { 
            $0.name.lowercased().contains(lowercaseName)
        }
    }
    
    /// 利用可能なカテゴリを取得
    /// - Returns: 現在利用可能な家具カテゴリの配列
    func getAvailableCategories() -> [FurnitureCategory] {
        let categories = Set(availableFurniture.map { $0.category })
        return Array(categories).sorted { $0.rawValue < $1.rawValue }
    }
    
    // MARK: - Statistics
    
    /// キャッシュ統計情報を取得
    func getCacheStatistics() -> CacheStatistics {
        return CacheStatistics(
            totalCached: modelCache.count,
            maxCacheSize: maxCacheSize,
            cacheHitRate: calculateCacheHitRate()
        )
    }
    
    /// キャッシュヒット率を計算（簡易実装）
    private func calculateCacheHitRate() -> Double {
        // 実際の実装では、ヒット/ミスの統計を追跡する必要があります
        return modelCache.isEmpty ? 0.0 : 0.8 // プレースホルダ���値
    }
    
    /// キャッシュ統計情報
    struct CacheStatistics {
        let totalCached: Int
        let maxCacheSize: Int
        let cacheHitRate: Double
    }
    
    // MARK: - Metadata Access
    
    /// データベースメタデータを取得
    func getDatabaseMetadata() -> FurnitureDatabase.DatabaseMetadata? {
        return databaseMetadata
    }
    
    /// デフォルト寸法を取得
    func getDefaultDimensions() -> FurnitureModel.RealWorldSize {
        return databaseMetadata?.defaultDimensions?.realWorldSize ?? 
               FurnitureModel.RealWorldSize.defaultSize
    }
    
    /// デフォルトスケーリング設定を取得
    func getDefaultScaling() -> (defaultScale: Float, maxScale: Float, minScale: Float) {
        let defaultScaling = databaseMetadata?.defaultScaling
        return (
            defaultScale: defaultScaling?.defaultScale ?? 1.0,
            maxScale: defaultScaling?.maxScale ?? 2.0,
            minScale: defaultScaling?.minScale ?? 0.5
        )
    }
    
    /// サポートされているカテゴリを取得
    func getSupportedCategories() -> [String] {
        return databaseMetadata?.supportedCategories ?? []
    }
    
    /// モデルIDと実寸法の紐付けを検証
    func validateModelDimensionBinding(_ model: FurnitureModel) -> ModelDimensionValidationResult {
        let issues: [String] = []
        var warnings: [String] = []
        
        // 基本的な寸法チェック
        if !model.realWorldSize.isValid {
            warnings.append("実世界サイズが現実的でない可能性があります")
        }
        
        // カテゴリ別の寸法チェック
        let categoryExpectedSize = getExpectedSizeForCategory(model.category)
        let sizeDifference = calculateSizeDifference(model.realWorldSize, expected: categoryExpectedSize)
        
        if sizeDifference > 0.5 { // 50%以上の差異
            warnings.append("カテゴリの一般的なサイズと大きく異なります")
        }
        
        // メタデータの整合性チェック
        if let metadata = model.metadata {
            if let weight = metadata.weight, weight <= 0 {
                warnings.append("重量が無効です")
            }
        }
        
        return ModelDimensionValidationResult(
            isValid: issues.isEmpty,
            issues: issues,
            warnings: warnings,
            sizeDifference: sizeDifference
        )
    }
    
    /// カテゴリの期待サイズを取得
    private func getExpectedSizeForCategory(_ category: FurnitureCategory) -> FurnitureModel.RealWorldSize {
        switch category {
        case .sofa:
            return FurnitureModel.RealWorldSize(width: 2.0, height: 0.8, depth: 0.9)
        case .table:
            return FurnitureModel.RealWorldSize(width: 1.5, height: 0.75, depth: 0.9)
        case .chair:
            return FurnitureModel.RealWorldSize(width: 0.6, height: 1.0, depth: 0.6)
        case .storage:
            return FurnitureModel.RealWorldSize(width: 1.0, height: 1.8, depth: 0.4)
        case .test:
            return FurnitureModel.RealWorldSize(width: 0.5, height: 0.5, depth: 0.5)
        }
    }
    
    /// サイズの差異を計算
    private func calculateSizeDifference(_ actual: FurnitureModel.RealWorldSize, expected: FurnitureModel.RealWorldSize) -> Float {
        let diffX = abs(actual.width - expected.width) / expected.width
        let diffY = abs(actual.height - expected.height) / expected.height
        let diffZ = abs(actual.depth - expected.depth) / expected.depth
        
        return (diffX + diffY + diffZ) / 3.0
    }
}

// MARK: - Supporting Types

/// 家具データベースのJSONファイル構造
struct FurnitureDatabase: Codable {
    let version: String
    let lastUpdated: String
    let metadata: DatabaseMetadata?
    let furniture: [FurnitureModel]
    
    /// データベースメタデータ
    struct DatabaseMetadata: Codable {
        let description: String?
        let defaultDimensions: DefaultDimensions?
        let defaultScaling: DefaultScaling?
        let supportedCategories: [String]?
        
        /// デフォルト寸法
        struct DefaultDimensions: Codable {
            let width: Float
            let height: Float
            let depth: Float
            
            var realWorldSize: FurnitureModel.RealWorldSize {
                return FurnitureModel.RealWorldSize(width: width, height: height, depth: depth)
            }
        }
        
        /// デフォルトスケーリング設定
        struct DefaultScaling: Codable {
            let defaultScale: Float
            let maxScale: Float
            let minScale: Float
        }
    }
}

/// モデル寸法検証結果
struct ModelDimensionValidationResult {
    let isValid: Bool
    let issues: [String]
    let warnings: [String]
    let sizeDifference: Float
    
    /// 検証レポートを生成
    var report: String {
        var report = "モデル寸法検証レポート:\n"
        
        if isValid {
            report += "✅ 検証成功\n"
        } else {
            report += "❌ 検証失敗\n"
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
        
        report += "サイズ差異: \(String(format: "%.1f", sizeDifference * 100))%"
        
        return report
    }
}

/// FurnitureRepositoryのエラータイプ
enum FurnitureRepositoryError: LocalizedError {
    case metadataFileNotFound
    case invalidJSONFormat
    case modelLoadingFailed(String)
    case cacheError(String)
    
    var errorDescription: String? {
        switch self {
        case .metadataFileNotFound:
            return "家具メタデータファイルが見つかりません"
        case .invalidJSONFormat:
            return "無効なJSONフォーマットです"
        case .modelLoadingFailed(let modelName):
            return "モデルの読み込みに失敗しました: \(modelName)"
        case .cacheError(let message):
            return "キャッシュエラー: \(message)"
        }
    }
}