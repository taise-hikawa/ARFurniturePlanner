//
//  MeshyAPIModels.swift
//  ARFurniturePlanner
//
//  Created by 樋川大聖 on 2025/10/10.
//

import Foundation

// MARK: - Image to 3D Request
struct ImageTo3DRequest: Codable {
    let imageUrl: String
    let enablePBR: Bool
    let shouldRemesh: Bool
    let shouldTexture: Bool
    let aiModel: String?
    let targetPolycount: Int?
    let symmetryMode: String?
    let texturePrompt: String?
    
    enum CodingKeys: String, CodingKey {
        case imageUrl = "image_url"
        case enablePBR = "enable_pbr"
        case shouldRemesh = "should_remesh"
        case shouldTexture = "should_texture"
        case aiModel = "ai_model"
        case targetPolycount = "target_polycount"
        case symmetryMode = "symmetry_mode"
        case texturePrompt = "texture_prompt"
    }
    
    init(
        imageUrl: String,
        enablePBR: Bool = true,
        shouldRemesh: Bool = true,
        shouldTexture: Bool = true,
        aiModel: String? = "meshy-5",
        targetPolycount: Int? = 50000,
        symmetryMode: String? = nil,
        texturePrompt: String? = nil
    ) {
        self.imageUrl = imageUrl
        self.enablePBR = enablePBR
        self.shouldRemesh = shouldRemesh
        self.shouldTexture = shouldTexture
        self.aiModel = aiModel
        self.targetPolycount = targetPolycount
        self.symmetryMode = symmetryMode
        self.texturePrompt = texturePrompt
    }
}

// MARK: - Task Response
struct MeshyTaskResponse: Codable {
    let result: String
    let data: MeshyTaskData?
    let message: String?
    let code: String?
}

// MARK: - Create Task Response
struct MeshyCreateTaskResponse: Codable {
    let result: String  // タスクID
}

struct MeshyTaskData: Codable, Identifiable {
    let id: String
    let status: TaskStatus
    let progress: Int?
    let startedAt: Int64?
    let finishedAt: Int64?
    let modelUrls: ModelUrls?
    let thumbnailUrl: String?
    let videoUrl: String?
    let createdAt: Int64
    let taskError: String?
    
    // 追加フィールド
    let name: String?
    let artStyle: String?
    let objectPrompt: String?
    let texturePrompt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, status, progress
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case modelUrls = "model_urls"
        case thumbnailUrl = "thumbnail_url"
        case videoUrl = "video_url"
        case createdAt = "created_at"
        case taskError = "task_error"
        case name
        case artStyle = "art_style"
        case objectPrompt = "object_prompt"
        case texturePrompt = "texture_prompt"
    }
    
    // 計算プロパティでDateに変換
    var startedAtDate: Date? {
        guard let startedAt = startedAt, startedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(startedAt) / 1000)
    }
    
    var finishedAtDate: Date? {
        guard let finishedAt = finishedAt, finishedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(finishedAt) / 1000)
    }
    
    var createdAtDate: Date {
        return Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
    }
}

// MARK: - Task Status
enum TaskStatus: String, Codable {
    case pending = "PENDING"
    case inProgress = "IN_PROGRESS"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case canceled = "CANCELED"
    case expired = "EXPIRED"
    
    var displayName: String {
        switch self {
        case .pending:
            return "待機中"
        case .inProgress:
            return "生成中"
        case .succeeded:
            return "完了"
        case .failed:
            return "失敗"
        case .canceled:
            return "キャンセル"
        case .expired:
            return "期限切れ"
        }
    }
    
    var isActive: Bool {
        switch self {
        case .pending, .inProgress:
            return true
        default:
            return false
        }
    }
    
    var isCompleted: Bool {
        switch self {
        case .succeeded, .failed, .canceled, .expired:
            return true
        default:
            return false
        }
    }
}

// MARK: - Model URLs
struct ModelUrls: Codable {
    let glb: String?
    let fbx: String?
    let obj: String?
    let usdz: String?
}

// MARK: - API Error
enum MeshyAPIError: LocalizedError {
    case invalidAPIKey
    case invalidURL
    case invalidImageFormat
    case quotaExceeded
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)
    case taskFailed(String)
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "APIキーが無効です"
        case .invalidURL:
            return "URLが無効です"
        case .invalidImageFormat:
            return "サポートされていない画像形式です"
        case .quotaExceeded:
            return "API利用制限に達しました"
        case .serverError(let message):
            return "サーバーエラー: \(message)"
        case .networkError(let error):
            return "ネットワークエラー: \(error.localizedDescription)"
        case .decodingError:
            return "データの解析に失敗しました"
        case .taskFailed(let reason):
            return "生成に失敗しました: \(reason)"
        case .unknownError(let message):
            return "不明なエラー: \(message)"
        }
    }
}

// MARK: - Generation Settings
struct GenerationSettings {
    let style: GenerationStyle
    let quality: GenerationQuality
    let enablePBR: Bool
    let shouldRemesh: Bool
    let shouldTexture: Bool
    let targetPolycount: Int?
    let symmetryMode: SymmetryMode?
    let texturePrompt: String?
    
    enum GenerationStyle: String, CaseIterable {
        case realistic = "realistic"
        case stylized = "stylized"
        case lowPoly = "low_poly"
        case cartoon = "cartoon"
        
        var displayName: String {
            switch self {
            case .realistic: return "リアル"
            case .stylized: return "スタイライズ"
            case .lowPoly: return "ローポリ"
            case .cartoon: return "カートゥーン"
            }
        }
        
        var texturePrompt: String? {
            switch self {
            case .realistic: return "realistic, photorealistic textures"
            case .stylized: return "stylized, artistic textures"
            case .lowPoly: return "simple, low poly style textures"
            case .cartoon: return "cartoon style, cel-shaded textures"
            }
        }
    }
    
    enum GenerationQuality: String, CaseIterable {
        case draft = "draft"
        case standard = "standard"
        case high = "high"
        
        var displayName: String {
            switch self {
            case .draft: return "ドラフト"
            case .standard: return "標準"
            case .high: return "高品質"
            }
        }
        
        var targetPolycount: Int {
            switch self {
            case .draft: return 10000
            case .standard: return 50000
            case .high: return 100000
            }
        }
        
        var estimatedTime: String {
            switch self {
            case .draft: return "1-2分"
            case .standard: return "3-5分"
            case .high: return "5-10分"
            }
        }
    }
    
    enum SymmetryMode: String {
        case none = "none"
        case x = "x"
        case y = "y"
        case z = "z"
        case xy = "xy"
        case xz = "xz"
        case yz = "yz"
        case xyz = "xyz"
    }
}