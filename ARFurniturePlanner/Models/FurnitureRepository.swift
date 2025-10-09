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
            let furnitureData = try await loadFurnitureFromJSON()
            
            // バリデーションを実行
            let validatedFurniture = furnitureData.compactMap { furniture -> FurnitureModel? in
                let validation = furniture.validate()
                if !validation.isValid {
                    print("警告: 家具データが無効です - \(furniture.name): \(validation.issues.joined(separator: ", "))")
                    return nil
                }
                return furniture
            }
            
            availableFurniture = validatedFurniture
            print("家具データベース読み込み完了: \(availableFurniture.count)個のアイテム")
            
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
    private func loadFurnitureFromJSON() async throws -> [FurnitureModel] {
        guard let url = Bundle.main.url(forResource: "furniture_metadata", withExtension: "json") else {
            throw FurnitureRepositoryError.metadataFileNotFound
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        
        let furnitureDatabase = try decoder.decode(FurnitureDatabase.self, from: data)
        return furnitureDatabase.furniture
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
}

// MARK: - Supporting Types

/// 家具データベースのJSONファイル構造
private struct FurnitureDatabase: Codable {
    let version: String
    let lastUpdated: String
    let furniture: [FurnitureModel]
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