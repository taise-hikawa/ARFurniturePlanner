//
//  MeshyAPISettingsView.swift
//  ARFurniturePlanner
//
//  Created by 樋川大聖 on 2025/10/10.
//

import SwiftUI

struct MeshyAPISettingsView: View {
    @StateObject private var apiService = MeshyAPIService.shared
    @State private var apiKey = ""
    @State private var showingAPIKey = false
    @State private var isTestingAPI = false
    @State private var testResult: TestResult?
    @Environment(\.dismiss) var dismiss
    
    enum TestResult {
        case success
        case failure(String)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Meshy AI APIキー")
                            .font(.headline)
                        
                        HStack {
                            if showingAPIKey {
                                TextField("APIキーを入力", text: $apiKey)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            } else {
                                SecureField("APIキーを入力", text: $apiKey)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            
                            Button(action: {
                                showingAPIKey.toggle()
                            }) {
                                Image(systemName: showingAPIKey ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Text("APIキーは[Meshy AI Dashboard](https://app.meshy.ai)から取得できます")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("API設定")
                }
                
                Section {
                    Button(action: {
                        saveAPIKey()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("APIキーを保存")
                        }
                    }
                    .disabled(apiKey.isEmpty)
                    
                    Button(action: {
                        testAPIConnection()
                    }) {
                        HStack {
                            if isTestingAPI {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("接続テスト中...")
                            } else {
                                Image(systemName: "network")
                                Text("接続テスト")
                            }
                        }
                    }
                    .disabled(apiKey.isEmpty || isTestingAPI)
                    
                    if let result = testResult {
                        HStack {
                            switch result {
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("接続成功")
                                    .foregroundColor(.green)
                            case .failure(let message):
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(message)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("アクション")
                }
                
                Section {
                    Link(destination: URL(string: "https://app.meshy.ai")!) {
                        HStack {
                            Text("Meshy AI Dashboardを開く")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                    
                    Link(destination: URL(string: "https://docs.meshy.ai/api/image-to-3d")!) {
                        HStack {
                            Text("APIドキュメントを見る")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                } header: {
                    Text("リンク")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• 画像から3Dモデルを生成できます")
                        Text("• 生成には通常3-5分かかります")
                        Text("• 生成されたモデルはUSDZ形式で保存されます")
                        Text("• 月間の生成回数には制限があります")
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                } header: {
                    Text("注意事項")
                }
            }
            .navigationTitle("Meshy API設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // 保存されているAPIキーがあれば読み込む
                if apiService.hasValidAPIKey() {
                    // APIキーは表示しない（セキュリティのため）
                    apiKey = "••••••••••••••••••••"
                }
            }
        }
    }
    
    private func saveAPIKey() {
        apiService.setAPIKey(apiKey)
        testResult = .success
    }
    
    private func testAPIConnection() {
        isTestingAPI = true
        testResult = nil
        
        // APIキーを一時的に設定してテスト
        apiService.setAPIKey(apiKey)
        
        Task {
            do {
                // 小さなテスト画像を作成
                let testImage = createTestImage()
                let settings = GenerationSettings(
                    style: .realistic,
                    quality: .draft,
                    enablePBR: false,
                    shouldRemesh: false,
                    shouldTexture: false,
                    targetPolycount: 1000,
                    symmetryMode: nil,
                    texturePrompt: nil
                )
                
                // APIをテスト（すぐにキャンセルする）
                let task = try await apiService.createImageTo3DTask(
                    image: testImage,
                    settings: settings,
                    furnitureName: "API Test"
                )
                
                // タスクをすぐにキャンセル
                try? await apiService.cancelTask(taskId: task.id)
                
                await MainActor.run {
                    testResult = .success
                    isTestingAPI = false
                }
            } catch let error as MeshyAPIError {
                await MainActor.run {
                    testResult = .failure(error.errorDescription ?? "接続エラー")
                    isTestingAPI = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure("接続失敗: \(error.localizedDescription)")
                    isTestingAPI = false
                }
            }
        }
    }
    
    private func createTestImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContext(size)
        UIColor.gray.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
}

#Preview {
    MeshyAPISettingsView()
}