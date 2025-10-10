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
    
    // タスクごとの生成情報を保持
    private struct TaskGenerationInfo {
        let furnitureName: String
        let sourceImage: UIImage?
        let settings: GenerationSettings
    }
    private var taskGenerationInfo: [String: TaskGenerationInfo] = [:]
    
    private init() {
        loadAPIKey()
        loadGenerationHistory()
        loadActiveTasks()
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
            
            // タスク情報を保存
            self.taskGenerationInfo[taskId] = TaskGenerationInfo(
                furnitureName: furnitureName,
                sourceImage: image,
                settings: settings
            )
            
            // アクティブタスクを永続化
            self.saveActiveTasks()
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
                // 監視を停止
                self.stopMonitoringTask(taskId: taskData.id)
                
                // アクティブタスクを更新して永続化
                self.saveActiveTasks()
                
                if taskData.status == .succeeded {
                    self.generationHistory.insert(taskData, at: 0)
                    self.saveGenerationHistory()
                    
                    // 生成されたモデルを保存
                    Task {
                        await self.handleSuccessfulGeneration(task: taskData)
                    }
                } else if taskData.status == .failed {
                    print("タスク失敗: \(taskData.taskError ?? "Unknown error")")
                    // 失敗したタスクの情報もクリーンアップ
                    self.taskGenerationInfo.removeValue(forKey: taskData.id)
                }
            } else {
                // 進行中のタスクも永続化を更新
                self.saveActiveTasks()
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
        
        // アクティブタスクから削除と監視停止
        DispatchQueue.main.async {
            self.activeTasks.removeValue(forKey: taskId)
            self.taskGenerationInfo.removeValue(forKey: taskId)
            self.saveActiveTasks()
            self.stopMonitoringTask(taskId: taskId)
        }
    }
    
    // MARK: - Task Monitoring
    
    private var taskMonitoringCancellables: [String: AnyCancellable] = [:]
    
    private func startMonitoringTask(taskId: String, furnitureName: String) {
        let cancellable = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    guard let self = self else { return }
                    
                    do {
                        let taskData = try await self.getTaskStatus(taskId: taskId)
                        
                        // タスクが完了したらタイマーを停止
                        if taskData.status.isCompleted {
                            self.stopMonitoringTask(taskId: taskId)
                        }
                    } catch {
                        print("Task monitoring error: \(error)")
                        // Task not foundエラーの場合は監視を停止
                        if case MeshyAPIError.serverError(let message) = error,
                           message.contains("Task not found") {
                            self.stopMonitoringTask(taskId: taskId)
                        }
                    }
                }
            }
        
        taskMonitoringCancellables[taskId] = cancellable
    }
    
    private func stopMonitoringTask(taskId: String) {
        taskMonitoringCancellables[taskId]?.cancel()
        taskMonitoringCancellables.removeValue(forKey: taskId)
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
    
    // MARK: - Model Saving
    
    private func handleSuccessfulGeneration(task: MeshyTaskData) async {
        do {
            // タスクに関連する情報を取得
            let taskInfo = taskGenerationInfo[task.id]
            let furnitureName = taskInfo?.furnitureName ?? "生成モデル"
            let settings = taskInfo?.settings ?? GenerationSettings(
                style: .realistic,
                quality: .high,
                enablePBR: true,
                shouldRemesh: true,
                shouldTexture: true,
                targetPolycount: 300000,
                symmetryMode: nil,
                texturePrompt: nil
            )
            
            // GeneratedModelManagerを使用してモデルを保存
            let generatedModel = try await GeneratedModelManager.shared.saveGeneratedModel(
                from: task,
                name: furnitureName,
                sourceImage: taskInfo?.sourceImage,
                settings: settings
            )
            
            // FurnitureRepositoryに同期
            await MainActor.run {
                FurnitureRepository.shared.syncGeneratedModels()
            }
            
            print("モデルの保存に成功: \(generatedModel.name)")
            
            // タスク情報をクリーンアップ
            taskGenerationInfo.removeValue(forKey: task.id)
            
        } catch {
            print("モデルの保存に失敗: \(error)")
        }
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
    
    // MARK: - Active Tasks Persistence
    
    private func loadActiveTasks() {
        // アクティブタスクを読み込む
        if let data = UserDefaults.standard.data(forKey: "MeshyActiveTasks") {
            let decoder = JSONDecoder()
            if let tasks = try? decoder.decode([String: MeshyTaskData].self, from: data) {
                activeTasks = tasks
                
                // 読み込んだタスクの監視を再開
                for (taskId, task) in tasks {
                    // 完了していないタスクのみ監視を再開
                    if !task.status.isCompleted {
                        // タスク情報を復元（名前のみ、画像やsettingsは復元不可）
                        let taskName = task.name ?? "復元されたタスク"
                        startMonitoringTask(taskId: taskId, furnitureName: taskName)
                    }
                }
            }
        }
        
        // タスク生成情報も復元（シンプル化のため基本情報のみ）
        if let infoData = UserDefaults.standard.data(forKey: "MeshyTaskGenerationInfo") {
            let decoder = JSONDecoder()
            if let info = try? decoder.decode([String: SimpleTaskInfo].self, from: infoData) {
                for (taskId, simpleInfo) in info {
                    taskGenerationInfo[taskId] = TaskGenerationInfo(
                        furnitureName: simpleInfo.furnitureName,
                        sourceImage: nil, // 画像は復元不可
                        settings: simpleInfo.settings
                    )
                }
            }
        }
    }
    
    private func saveActiveTasks() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(activeTasks) {
            UserDefaults.standard.set(data, forKey: "MeshyActiveTasks")
        }
        
        // タスク生成情報も保存（シンプル化のため基本情報のみ）
        var simpleTaskInfo: [String: SimpleTaskInfo] = [:]
        for (taskId, info) in taskGenerationInfo {
            simpleTaskInfo[taskId] = SimpleTaskInfo(
                furnitureName: info.furnitureName,
                settings: info.settings
            )
        }
        
        if let infoData = try? encoder.encode(simpleTaskInfo) {
            UserDefaults.standard.set(infoData, forKey: "MeshyTaskGenerationInfo")
        }
    }
    
    // タスク情報の永続化用構造体
    private struct SimpleTaskInfo: Codable {
        let furnitureName: String
        let settings: GenerationSettings
    }
}
