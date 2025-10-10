//
//  ImageTo3DGenerationView.swift
//  ARFurniturePlanner
//
//  Created by 樋川大聖 on 2025/10/10.
//

import SwiftUI
import PhotosUI

struct ImageTo3DGenerationView: View {
    @Binding var isPresented: Bool
    @Binding var selectedImage: UIImage?
    @State private var furnitureName = ""
    @State private var selectedStyle = GenerationSettings.GenerationStyle.realistic
    @State private var selectedQuality = GenerationSettings.GenerationQuality.standard
    @State private var autoScale = true
    @State private var estimatedWidth: String = "50"
    @State private var estimatedHeight: String = "80"
    @State private var estimatedDepth: String = "50"
    @State private var showingImagePicker = false
    @State private var isGenerating = false
    @State private var generationProgress: Double = 0
    @State private var generationStatus = "準備中..."
    @State private var currentTaskId: String?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingAPISettings = false
    @StateObject private var apiService = MeshyAPIService.shared
    @StateObject private var modelManager = GeneratedModelManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // 画像選択セクション
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ソース画像")
                            .font(.headline)
                        
                        if let image = selectedImage {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 300)
                                    .cornerRadius(12)
                                
                                Button(action: {
                                    showingImagePicker = true
                                }) {
                                    Label("変更", systemImage: "pencil.circle.fill")
                                        .font(.caption)
                                        .padding(8)
                                        .background(Color.black.opacity(0.6))
                                        .foregroundColor(.white)
                                        .cornerRadius(20)
                                }
                                .padding(12)
                            }
                        } else {
                            Button(action: {
                                showingImagePicker = true
                            }) {
                                VStack(spacing: 16) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 50))
                                        .foregroundColor(.gray)
                                    
                                    Text("画像を選択")
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity, minHeight: 200)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [10]))
                                        .foregroundColor(.gray.opacity(0.3))
                                )
                            }
                        }
                    }
                    
                    // 基本設定セクション
                    VStack(alignment: .leading, spacing: 16) {
                        Text("基本設定")
                            .font(.headline)
                        
                        // 家具名
                        VStack(alignment: .leading, spacing: 8) {
                            Text("家具名")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            TextField("例: モダンチェア", text: $furnitureName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        // 生成スタイル
                        VStack(alignment: .leading, spacing: 8) {
                            Text("スタイル")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Picker("スタイル", selection: $selectedStyle) {
                                ForEach(GenerationSettings.GenerationStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        // 品質設定
                        VStack(alignment: .leading, spacing: 8) {
                            Text("品質")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Picker("品質", selection: $selectedQuality) {
                                ForEach(GenerationSettings.GenerationQuality.allCases, id: \.self) { quality in
                                    Text(quality.displayName).tag(quality)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
                    
                    // サイズ設定セクション
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("推定サイズ")
                                .font(.headline)
                            
                            Spacer()
                            
                            Toggle("自動スケール", isOn: $autoScale)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                        }
                        
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("幅 (cm)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                TextField("50", text: $estimatedWidth)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numberPad)
                                    .disabled(autoScale)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("高さ (cm)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                TextField("80", text: $estimatedHeight)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numberPad)
                                    .disabled(autoScale)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("奥行 (cm)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                TextField("50", text: $estimatedDepth)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numberPad)
                                    .disabled(autoScale)
                            }
                        }
                        
                        if autoScale {
                            Text("※ 自動スケールが有効です。生成後に適切なサイズに調整されます。")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // 生成情報
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle")
                            Text("生成について")
                        }
                        .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text("推定時間: \(estimatedTime)")
                                    .font(.caption)
                            }
                            .foregroundColor(.gray)
                            
                            HStack {
                                Image(systemName: "dollarsign.circle")
                                    .font(.caption)
                                Text("推定コスト: \(estimatedCost)")
                                    .font(.caption)
                            }
                            .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("3D家具を生成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("生成開始") {
                        if apiService.hasValidAPIKey() {
                            startGeneration()
                        } else {
                            showingAPISettings = true
                        }
                    }
                    .disabled(selectedImage == nil || furnitureName.isEmpty || isGenerating)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showingAPISettings) {
                MeshyAPISettingsView()
            }
            .alert("エラー", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .overlay {
                if isGenerating {
                    GenerationProgressOverlay(
                        progress: generationProgress,
                        status: generationStatus,
                        onCancel: {
                            cancelGeneration()
                        }
                    )
                }
            }
        }
    }
    
    private var estimatedTime: String {
        return selectedQuality.estimatedTime
    }
    
    private var estimatedCost: String {
        switch selectedQuality {
        case .draft:
            return "¥50"
        case .standard:
            return "¥100"
        case .high:
            return "¥200"
        }
    }
    
    private func startGeneration() {
        guard let image = selectedImage else { return }
        
        isGenerating = true
        generationProgress = 0
        generationStatus = "画像をアップロード中..."
        
        let settings = GenerationSettings(
            style: selectedStyle,
            quality: selectedQuality,
            enablePBR: true,
            shouldRemesh: true,
            shouldTexture: true,
            targetPolycount: selectedQuality.targetPolycount,
            symmetryMode: nil,
            texturePrompt: nil
        )
        
        Task {
            do {
                // APIキーの再確認
                if !apiService.hasValidAPIKey() {
                    await MainActor.run {
                        isGenerating = false
                        errorMessage = "APIキーが設定されていません"
                        showingError = true
                        showingAPISettings = true
                    }
                    return
                }
                
                // Meshy APIを呼び出してタスクを作成
                let task = try await apiService.createImageTo3DTask(
                    image: image,
                    settings: settings,
                    furnitureName: furnitureName
                )
                
                currentTaskId = task.id
                
                // タスクの進捗を監視
                await monitorTaskProgress(taskId: task.id)
                
            } catch let meshyError as MeshyAPIError {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = meshyError.errorDescription ?? "生成エラー"
                    showingError = true
                    
                    // APIキーエラーの場合は設定画面を表示
                    if case .invalidAPIKey = meshyError {
                        showingAPISettings = true
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = "エラー: \(error.localizedDescription)"
                    showingError = true
                    print("Generation error: \(error)")
                }
            }
        }
    }
    
    private func monitorTaskProgress(taskId: String) async {
        var retryCount = 0
        let maxRetries = 60 // 最大5分間監視
        
        while retryCount < maxRetries {
            do {
                let task = try await apiService.getTaskStatus(taskId: taskId)
                
                await MainActor.run {
                    // 進捗を更新
                    if let progress = task.progress {
                        generationProgress = Double(progress) / 100.0
                    }
                    
                    // ステータスを更新
                    switch task.status {
                    case .pending:
                        generationStatus = "待機中..."
                    case .inProgress:
                        if generationProgress < 0.3 {
                            generationStatus = "3Dモデルを生成中..."
                        } else if generationProgress < 0.7 {
                            generationStatus = "テクスチャを生成中..."
                        } else {
                            generationStatus = "最終処理中..."
                        }
                    case .succeeded:
                        generationStatus = "完了！"
                        Task {
                            await saveGeneratedModel(task: task)
                        }
                        return
                    case .failed:
                        isGenerating = false
                        errorMessage = "生成に失敗しました"
                        showingError = true
                        return
                    case .canceled:
                        isGenerating = false
                        return
                    case .expired:
                        isGenerating = false
                        errorMessage = "タスクの有効期限が切れました"
                        showingError = true
                        return
                    }
                }
                
                // 5秒待機して再チェック
                try await Task.sleep(nanoseconds: 5_000_000_000)
                retryCount += 1
                
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
                return
            }
        }
        
        // タイムアウト
        await MainActor.run {
            isGenerating = false
            errorMessage = "生成がタイムアウトしました"
            showingError = true
        }
    }
    
    private func saveGeneratedModel(task: MeshyTaskData) async {
        do {
            let settings = GenerationSettings(
                style: selectedStyle,
                quality: selectedQuality,
                enablePBR: true,
                shouldRemesh: true,
                shouldTexture: true,
                targetPolycount: selectedQuality.targetPolycount,
                symmetryMode: nil,
                texturePrompt: nil
            )
            
            _ = try await modelManager.saveGeneratedModel(
                from: task,
                name: furnitureName,
                sourceImage: selectedImage,
                settings: settings
            )
            
            await MainActor.run {
                isGenerating = false
                isPresented = false
            }
            
        } catch {
            await MainActor.run {
                isGenerating = false
                errorMessage = "モデルの保存に失敗しました: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    private func cancelGeneration() {
        guard let taskId = currentTaskId else {
            isGenerating = false
            return
        }
        
        Task {
            do {
                try await apiService.cancelTask(taskId: taskId)
                await MainActor.run {
                    isGenerating = false
                }
            } catch {
                print("Failed to cancel task: \(error)")
                await MainActor.run {
                    isGenerating = false
                }
            }
        }
    }
}

// MARK: - 生成進捗オーバーレイ
struct GenerationProgressOverlay: View {
    let progress: Double
    let status: String
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // プログレスインジケーター
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: progress)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                Text(status)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Button(action: onCancel) {
                    Text("キャンセル")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.8))
            )
        }
    }
}

#Preview {
    ImageTo3DGenerationView(
        isPresented: .constant(true),
        selectedImage: .constant(nil)
    )
}