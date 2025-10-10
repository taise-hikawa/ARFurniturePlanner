//
//  MeshyAPIService.swift
//  ARFurniturePlanner
//
//  Created by 樋川大聖 on 2025/10/10.
//

import Foundation
import UIKit
import Combine

class MeshyAPIService: ObservableObject {
    static let shared = MeshyAPIService()
    
    private let baseURL = "https://api.meshy.ai/openapi/v1"
    private var apiKey: String?
    private let session = URLSession.shared
    private var cancellables = Set<AnyCancellable>()
    
    // 生成タスクの追跡
    @Published var activeTasks: [String: MeshyTaskData] = [:]
    @Published var generationHistory: [MeshyTaskData] = []
    
    private init() {
        loadAPIKey()
        loadGenerationHistory()
    }
    
    // MARK: - API Key Management
    
    func setAPIKey(_ key: String) {
        apiKey = key
        saveAPIKey(key)
    }
    
    func hasValidAPIKey() -> Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    private func loadAPIKey() {
        // UserDefaultsから読み込み（本番環境ではKeychainを使用推奨）
        if let key = UserDefaults.standard.string(forKey: "MeshyAPIKey") {
            apiKey = key
        }
    }
    
    private func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "MeshyAPIKey")
    }
    
    // MARK: - Image Upload
    
    /// 画像をBase64形式に変換
    private func convertImageToBase64(image: UIImage) -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }
        let base64String = imageData.base64EncodedString()
        return "data:image/jpeg;base64,\(base64String)"
    }
    
    // MARK: - API Requests
    
    /// 画像から3Dモデルを生成するタスクを作成
    func createImageTo3DTask(
        image: UIImage,
        settings: GenerationSettings,
        furnitureName: String
    ) async throws -> MeshyTaskData {
        guard let apiKey = apiKey else {
            throw MeshyAPIError.invalidAPIKey
        }
        
        // 画像をBase64に変換
        guard let imageBase64 = convertImageToBase64(image: image) else {
            throw MeshyAPIError.invalidImageFormat
        }
        
        // リクエストボディを作成
        let request = ImageTo3DRequest(
            imageUrl: imageBase64,
            enablePBR: settings.enablePBR,
            shouldRemesh: settings.shouldRemesh,
            shouldTexture: settings.shouldTexture,
            aiModel: "latest",
            targetPolycount: settings.quality.targetPolycount,
            symmetryMode: settings.symmetryMode?.rawValue,
            texturePrompt: combineTexturePrompts(settings: settings)
        )
        
        // URLリクエストを作成
        guard let url = URL(string: "\(baseURL)/image-to-3d") else {
            throw MeshyAPIError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        
        // APIリクエストを送信
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            print("Network request failed: \(error)")
            throw MeshyAPIError.networkError(error)
        }
        
        // レスポンスをチェック
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeshyAPIError.unknownError("Invalid response")
        }
        
        print("Meshy API Response Status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 401 {
            throw MeshyAPIError.invalidAPIKey
        } else if httpResponse.statusCode == 429 {
            throw MeshyAPIError.quotaExceeded
        } else if httpResponse.statusCode >= 400 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("Meshy API Error Response: \(errorMessage)")
            throw MeshyAPIError.serverError(errorMessage)
        }
        
        // デバッグ用：成功レスポンスを出力
        if let responseString = String(data: data, encoding: .utf8) {
            print("Meshy API Success Response: \(responseString)")
        }
        
        // レスポンスをデコード
        let decoder = JSONDecoder()
        // 日付はUnixタイムスタンプとして扱うので、特別な設定は不要
        
        // 作成時は{"result": "task-id"}の形式で返される
        let createResponse = try decoder.decode(MeshyCreateTaskResponse.self, from: data)
        let taskId = createResponse.result
        
        print("Created task with ID: \(taskId)")
        
        // 初期タスクデータを作成
        let taskData = MeshyTaskData(
            id: taskId,
            status: .pending,
            progress: 0,
            startedAt: nil,
            finishedAt: nil,
            modelUrls: nil,
            thumbnailUrl: nil,
            videoUrl: nil,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            taskError: nil,
            name: furnitureName,
            artStyle: nil,
            objectPrompt: nil,
            texturePrompt: nil
        )
        
        // アクティブタスクに追加
        DispatchQueue.main.async {
            self.activeTasks[taskId] = taskData
        }
        
        // タスクの進捗を監視開始
        startMonitoringTask(taskId: taskId, furnitureName: furnitureName)
        
        return taskData
    }
    
    /// タスクのステータスを取得
    func getTaskStatus(taskId: String) async throws -> MeshyTaskData {
        guard let apiKey = apiKey else {
            throw MeshyAPIError.invalidAPIKey
        }
        
        guard let url = URL(string: "\(baseURL)/image-to-3d/\(taskId)") else {
            throw MeshyAPIError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeshyAPIError.unknownError("Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MeshyAPIError.serverError(errorMessage)
        }
        
        // デバッグ用：レスポンスを出力
        if let responseString = String(data: data, encoding: .utf8) {
            print("Get task status response: \(responseString)")
        }
        
        let decoder = JSONDecoder()
        // 日付はUnixタイムスタンプとして扱う
        
        // タスクステータスは直接MeshyTaskDataの形式で返される
        let taskData = try decoder.decode(MeshyTaskData.self, from: data)
        
        // タスクステータスを更新
        DispatchQueue.main.async {
            self.activeTasks[taskData.id] = taskData
            
            // 完了したタスクは履歴に追加
            if taskData.status.isCompleted {
                self.activeTasks.removeValue(forKey: taskData.id)
                if taskData.status == .succeeded {
                    self.generationHistory.insert(taskData, at: 0)
                    self.saveGenerationHistory()
                }
            }
        }
        
        return taskData
    }
    
    /// タスクをキャンセル
    func cancelTask(taskId: String) async throws {
        guard let apiKey = apiKey else {
            throw MeshyAPIError.invalidAPIKey
        }
        
        guard let url = URL(string: "\(baseURL)/image-to-3d/\(taskId)") else {
            throw MeshyAPIError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "DELETE"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeshyAPIError.unknownError("Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            throw MeshyAPIError.serverError("Failed to cancel task")
        }
        
        // アクティブタスクから削除
        DispatchQueue.main.async {
            self.activeTasks.removeValue(forKey: taskId)
        }
    }
    
    // MARK: - Task Monitoring
    
    private func startMonitoringTask(taskId: String, furnitureName: String) {
        Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    do {
                        let taskData = try await self?.getTaskStatus(taskId: taskId)
                        
                        // タスクが完了したらタイマーを停止
                        if taskData?.status.isCompleted == true {
                            // キャンセル処理はgetTaskStatus内で行われる
                        }
                    } catch {
                        print("Task monitoring error: \(error)")
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Model Download
    
    /// 生成された3Dモデルをダウンロード
    func downloadModel(from urlString: String, taskId: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw MeshyAPIError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MeshyAPIError.serverError("Failed to download model")
        }
        
        // ローカルに保存
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsPath = documentsPath.appendingPathComponent("GeneratedModels")
        
        // ディレクトリがなければ作成
        try? FileManager.default.createDirectory(at: modelsPath, withIntermediateDirectories: true)
        
        let fileURL = modelsPath.appendingPathComponent("\(taskId).usdz")
        try data.write(to: fileURL)
        
        return fileURL
    }
    
    // MARK: - Helper Methods
    
    private func combineTexturePrompts(settings: GenerationSettings) -> String? {
        var prompts: [String] = []
        
        if let stylePrompt = settings.style.texturePrompt {
            prompts.append(stylePrompt)
        }
        
        if let customPrompt = settings.texturePrompt, !customPrompt.isEmpty {
            prompts.append(customPrompt)
        }
        
        return prompts.isEmpty ? nil : prompts.joined(separator: ", ")
    }
    
    // MARK: - History Management
    
    private func loadGenerationHistory() {
        if let data = UserDefaults.standard.data(forKey: "MeshyGenerationHistory") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let history = try? decoder.decode([MeshyTaskData].self, from: data) {
                generationHistory = history
            }
        }
    }
    
    private func saveGenerationHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(generationHistory) {
            UserDefaults.standard.set(data, forKey: "MeshyGenerationHistory")
        }
    }
    
    func clearHistory() {
        generationHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "MeshyGenerationHistory")
    }
}
