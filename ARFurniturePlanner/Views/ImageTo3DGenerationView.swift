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
    @State private var selectedStyle = GenerationStyle.realistic
    @State private var selectedQuality = GenerationQuality.medium
    @State private var autoScale = true
    @State private var estimatedWidth: String = "50"
    @State private var estimatedHeight: String = "80"
    @State private var estimatedDepth: String = "50"
    @State private var showingImagePicker = false
    @State private var isGenerating = false
    @State private var generationProgress: Double = 0
    @State private var generationStatus = "準備中..."
    
    enum GenerationStyle: String, CaseIterable {
        case realistic = "リアル"
        case stylized = "スタイライズ"
        case lowPoly = "ローポリ"
        case cartoon = "カートゥーン"
    }
    
    enum GenerationQuality: String, CaseIterable {
        case draft = "ドラフト"
        case medium = "標準"
        case high = "高品質"
    }
    
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
                                ForEach(GenerationStyle.allCases, id: \.self) { style in
                                    Text(style.rawValue).tag(style)
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
                                ForEach(GenerationQuality.allCases, id: \.self) { quality in
                                    Text(quality.rawValue).tag(quality)
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
                        startGeneration()
                    }
                    .disabled(selectedImage == nil || furnitureName.isEmpty || isGenerating)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $selectedImage)
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
        switch selectedQuality {
        case .draft:
            return "1-2分"
        case .medium:
            return "3-5分"
        case .high:
            return "5-10分"
        }
    }
    
    private var estimatedCost: String {
        switch selectedQuality {
        case .draft:
            return "¥50"
        case .medium:
            return "¥100"
        case .high:
            return "¥200"
        }
    }
    
    private func startGeneration() {
        isGenerating = true
        generationProgress = 0
        generationStatus = "画像をアップロード中..."
        
        // TODO: 実際のMeshy API呼び出し
        // 現在はモック処理
        simulateGeneration()
    }
    
    private func simulateGeneration() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            generationProgress += 0.01
            
            if generationProgress < 0.2 {
                generationStatus = "画像をアップロード中..."
            } else if generationProgress < 0.5 {
                generationStatus = "3Dモデルを生成中..."
            } else if generationProgress < 0.8 {
                generationStatus = "テクスチャを最適化中..."
            } else if generationProgress < 0.95 {
                generationStatus = "最終処理中..."
            } else {
                generationStatus = "完了！"
                timer.invalidate()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isGenerating = false
                    isPresented = false
                }
            }
        }
    }
    
    private func cancelGeneration() {
        isGenerating = false
        // TODO: 実際のキャンセル処理
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