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
    @Binding var selectedTab: Int  // 親ビューのタブ選択を制御
    @State private var furnitureName = ""
    @State private var selectedStyle = GenerationSettings.GenerationStyle.realistic
    @State private var selectedQuality = GenerationSettings.GenerationQuality.high
    @State private var autoScale = true
    @State private var estimatedWidth: String = "50"
    @State private var estimatedHeight: String = "80"
    @State private var estimatedDepth: String = "50"
    @State private var showingImagePicker = false
    @State private var showingImageSourceSelection = false
    @State private var currentTaskId: String?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingAPISettings = false
    @StateObject private var apiService = MeshyAPIService.shared
    @StateObject private var modelManager = GeneratedModelManager.shared
    @EnvironmentObject var repository: FurnitureRepository
    
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
                                    showingImageSourceSelection = true
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
                                showingImageSourceSelection = true
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
                    .disabled(selectedImage == nil || furnitureName.isEmpty)
                }
            }
            .sheet(isPresented: $showingImageSourceSelection) {
                ImageSourceSelectionView(
                    isPresented: $showingImageSourceSelection,
                    selectedImage: $selectedImage
                )
            }
            .sheet(isPresented: $showingAPISettings) {
                MeshyAPISettingsView()
            }
            .alert("エラー", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
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
                
                // シートを閉じて「生成中」タブに切り替え
                await MainActor.run {
                    isPresented = false
                    selectedTab = 2  // 生成中タブに切り替え
                }
                
            } catch let meshyError as MeshyAPIError {
                await MainActor.run {
                    errorMessage = meshyError.errorDescription ?? "生成エラー"
                    showingError = true
                    
                    // APIキーエラーの場合は設定画面を表示
                    if case .invalidAPIKey = meshyError {
                        showingAPISettings = true
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "エラー: \(error.localizedDescription)"
                    showingError = true
                    print("Generation error: \(error)")
                }
            }
        }
    }
}

#Preview {
    ImageTo3DGenerationView(
        isPresented: .constant(true),
        selectedImage: .constant(nil),
        selectedTab: .constant(0)
    )
}
