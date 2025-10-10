//
//  GeneratedModelManager.swift
//  ARFurniturePlanner
//
//  Created by 樋川大聖 on 2025/10/10.
//

import Foundation
import RealityKit
import UIKit

/// 生成された3Dモデルを表す構造体
struct GeneratedFurnitureModel: Identifiable, Codable {
    let id: String
    var name: String
    let taskId: String
    let localModelPath: String?
    let thumbnailPath: String?
    let generatedDate: Date
    let metadata: GenerationMetadata
    var isAvailableOffline: Bool
    
    struct GenerationMetadata: Codable {
        let style: String
        let quality: String
        let polycount: Int?
        let sourceImagePath: String?
    }
}

/// 生成されたモデルを管理するクラス
class GeneratedModelManager: ObservableObject {
    static let shared = GeneratedModelManager()
    
    @Published var generatedModels: [GeneratedFurnitureModel] = []
    private let documentsDirectory: URL
    private let modelsDirectory: URL
    private let thumbnailsDirectory: URL
    private let imagesDirectory: URL
    
    private init() {
        // ディレクトリの初期化
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        modelsDirectory = documentsDirectory.appendingPathComponent("GeneratedModels")
        thumbnailsDirectory = documentsDirectory.appendingPathComponent("GeneratedThumbnails")
        imagesDirectory = documentsDirectory.appendingPathComponent("SourceImages")
        
        // ディレクトリを作成
        createDirectories()
        
        // 保存されたモデルを読み込み
        loadGeneratedModels()
    }
    
    private func createDirectories() {
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Model Management
    
    /// Meshyタスクから生成されたモデルを保存
    func saveGeneratedModel(
        from task: MeshyTaskData,
        name: String,
        sourceImage: UIImage?,
        settings: GenerationSettings
    ) async throws -> GeneratedFurnitureModel {
        
        // USDZモデルをダウンロード
        guard let usdzURL = task.modelUrls?.usdz else {
            throw MeshyAPIError.unknownError("USDZ URL not available")
        }
        
        let modelURL = try await MeshyAPIService.shared.downloadModel(from: usdzURL, taskId: task.id)
        
        // サムネイルを保存
        var thumbnailPath: String? = nil
        if let thumbnailURL = task.thumbnailUrl,
           let url = URL(string: thumbnailURL) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let thumbnailFileName = "\(task.id)_thumb.jpg"
                let thumbnailFileURL = thumbnailsDirectory.appendingPathComponent(thumbnailFileName)
                try data.write(to: thumbnailFileURL)
                thumbnailPath = thumbnailFileName
            } catch {
                print("Failed to save thumbnail: \(error)")
            }
        }
        
        // ソース画像を保存
        var sourceImagePath: String? = nil
        if let image = sourceImage {
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                let imageFileName = "\(task.id)_source.jpg"
                let imageFileURL = imagesDirectory.appendingPathComponent(imageFileName)
                try? imageData.write(to: imageFileURL)
                sourceImagePath = imageFileName
            }
        }
        
        // モデル情報を作成
        let generatedModel = GeneratedFurnitureModel(
            id: UUID().uuidString,
            name: name,
            taskId: task.id,
            localModelPath: "\(task.id).usdz",
            thumbnailPath: thumbnailPath,
            generatedDate: task.finishedAtDate ?? Date(),
            metadata: GeneratedFurnitureModel.GenerationMetadata(
                style: settings.style.rawValue,
                quality: settings.quality.rawValue,
                polycount: settings.targetPolycount,
                sourceImagePath: sourceImagePath
            ),
            isAvailableOffline: true
        )
        
        // モデルリストに追加
        DispatchQueue.main.async {
            self.generatedModels.insert(generatedModel, at: 0)
            self.saveGeneratedModels()
        }
        
        return generatedModel
    }
    
    /// FurnitureModelに変換
    func convertToFurnitureModel(_ generatedModel: GeneratedFurnitureModel) -> FurnitureModel? {
        guard let modelPath = generatedModel.localModelPath else { return nil }
        
        let furnitureModel = FurnitureModel(
            id: generatedModel.id,
            name: generatedModel.name,
            category: .test, // 生成されたモデルは「テスト」カテゴリに分類
            modelFileName: modelPath,
            thumbnailFileName: generatedModel.thumbnailPath,
            realWorldSize: FurnitureModel.RealWorldSize(width: 1.0, height: 1.0, depth: 1.0), // デフォルトサイズ
            defaultScale: 1.0,
            maxScale: 2.0,
            minScale: 0.5,
            metadata: FurnitureModel.FurnitureMetadata(
                description: "Meshy AIで生成された家具",
                tags: ["生成", "カスタム"],
                materialType: "不明",
                weight: 1.0,
                scalingStrategy: "uniform",
                accuracyLevel: "medium"
            )
        )
        
        return furnitureModel
    }
    
    /// モデルを読み込み
    func loadModel(generatedModel: GeneratedFurnitureModel) async -> ModelEntity? {
        guard let modelPath = generatedModel.localModelPath else { return nil }
        
        let fullPath = modelsDirectory.appendingPathComponent(modelPath)
        
        do {
            let entity = try await ModelEntity(contentsOf: fullPath)
            
            // コリジョン形状を生成
            await entity.generateCollisionShapes(recursive: true)
            
            return entity
        } catch {
            print("Failed to load generated model: \(error)")
            return nil
        }
    }
    
    /// モデルを削除
    func deleteModel(_ model: GeneratedFurnitureModel) {
        // ファイルを削除
        if let modelPath = model.localModelPath {
            let modelURL = modelsDirectory.appendingPathComponent(modelPath)
            try? FileManager.default.removeItem(at: modelURL)
        }
        
        if let thumbnailPath = model.thumbnailPath {
            let thumbnailURL = thumbnailsDirectory.appendingPathComponent(thumbnailPath)
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
        
        if let sourceImagePath = model.metadata.sourceImagePath {
            let imageURL = imagesDirectory.appendingPathComponent(sourceImagePath)
            try? FileManager.default.removeItem(at: imageURL)
        }
        
        // リストから削除
        generatedModels.removeAll { $0.id == model.id }
        saveGeneratedModels()
    }
    
    /// モデル名を更新
    func updateModelName(_ model: GeneratedFurnitureModel, newName: String) {
        if let index = generatedModels.firstIndex(where: { $0.id == model.id }) {
            generatedModels[index].name = newName
            saveGeneratedModels()
        }
    }
    
    // MARK: - Persistence
    
    private func loadGeneratedModels() {
        let url = documentsDirectory.appendingPathComponent("generatedModels.json")
        
        guard let data = try? Data(contentsOf: url) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let models = try? decoder.decode([GeneratedFurnitureModel].self, from: data) {
            generatedModels = models
        }
    }
    
    private func saveGeneratedModels() {
        let url = documentsDirectory.appendingPathComponent("generatedModels.json")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        if let data = try? encoder.encode(generatedModels) {
            try? data.write(to: url)
        }
    }
    
    // MARK: - Thumbnail Loading
    
    func loadThumbnail(for model: GeneratedFurnitureModel) -> UIImage? {
        guard let thumbnailPath = model.thumbnailPath else { return nil }
        
        let url = thumbnailsDirectory.appendingPathComponent(thumbnailPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        return UIImage(data: data)
    }
    
    func loadSourceImage(for model: GeneratedFurnitureModel) -> UIImage? {
        guard let imagePath = model.metadata.sourceImagePath else { return nil }
        
        let url = imagesDirectory.appendingPathComponent(imagePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        return UIImage(data: data)
    }
}