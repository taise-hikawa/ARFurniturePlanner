//
//  FurnitureManagementView.swift
//  ARFurniturePlanner
//
//  Created by 樋川大聖 on 2025/10/10.
//

import SwiftUI
import PhotosUI

struct FurnitureManagementView: View {
    @StateObject private var furnitureRepository = FurnitureRepository.shared
    @StateObject private var modelManager = GeneratedModelManager.shared
    @StateObject private var apiService = MeshyAPIService.shared
    @State private var selectedTab = 0
    @State private var showingImageTo3D = false
    @State private var selectedImage: UIImage?
    @State private var showingARView = false
    @State private var searchText = ""
    @State private var showingAPISettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // タブ選択
                Picker("", selection: $selectedTab) {
                    Text("ライブラリ").tag(0)
                    Text("生成済み").tag(1)
                    Text("生成中").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // 検索バー
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("家具を検索", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)
                
                // コンテンツエリア
                if selectedTab == 0 {
                    // ライブラリタブ
                    LibraryTabView(furnitureRepository: furnitureRepository, searchText: searchText)
                } else if selectedTab == 1 {
                    // 生成済みタブ
                    GeneratedTabView()
                } else {
                    // 生成中タブ
                    GeneratingTabView()
                }
                
                Spacer()
                
                // 下部ボタン
                VStack(spacing: 16) {
                    // APIキー設定が必要な場合の表示
                    if !apiService.hasValidAPIKey() {
                        Button(action: {
                            showingAPISettings = true
                        }) {
                            HStack {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 20))
                                Text("APIキーを設定")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    
                    // 画像から3D生成ボタン
                    Button(action: {
                        if apiService.hasValidAPIKey() {
                            showingImageTo3D = true
                        } else {
                            showingAPISettings = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                            Text("画像から3D家具を生成")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(apiService.hasValidAPIKey() ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    // ARビューを開くボタン
                    Button(action: {
                        showingARView = true
                    }) {
                        HStack {
                            Image(systemName: "arkit")
                                .font(.system(size: 20))
                            Text("ARで配置する")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("家具管理")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                syncGeneratedModelsToRepository()
            }
            .sheet(isPresented: $showingImageTo3D) {
                ImageTo3DGenerationView(
                    isPresented: $showingImageTo3D,
                    selectedImage: $selectedImage
                )
                .environmentObject(furnitureRepository)
            }
            .fullScreenCover(isPresented: $showingARView) {
                ContentView()
            }
            .sheet(isPresented: $showingAPISettings) {
                MeshyAPISettingsView()
            }
        }
    }
    
    // 生成済みモデルをFurnitureRepositoryに同期
    private func syncGeneratedModelsToRepository() {
        for generatedModel in modelManager.generatedModels {
            // FurnitureModelに変換
            let furnitureModel = FurnitureModel(
                id: generatedModel.id,
                name: generatedModel.name,
                category: .test, // デフォルトカテゴリ
                modelFileName: generatedModel.localModelPath ?? "",
                thumbnailFileName: generatedModel.thumbnailPath,
                realWorldSize: FurnitureModel.RealWorldSize(width: 1.0, height: 1.0, depth: 1.0),
                defaultScale: 1.0,
                maxScale: 2.0,
                minScale: 0.5,
                metadata: FurnitureModel.FurnitureMetadata(
                    description: "Meshy AIで生成された家具",
                    tags: ["生成", "カスタム", "meshy-generated"],
                    materialType: "3D生成",
                    weight: nil,
                    scalingStrategy: "uniform",
                    accuracyLevel: generatedModel.metadata.quality
                )
            )
            
            furnitureRepository.addGeneratedModel(furnitureModel)
        }
    }
}

// MARK: - ライブラリタブ
struct LibraryTabView: View {
    @ObservedObject var furnitureRepository: FurnitureRepository
    let searchText: String
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var filteredFurniture: [FurnitureModel] {
        if searchText.isEmpty {
            return furnitureRepository.availableFurniture
        }
        return furnitureRepository.availableFurniture.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.category.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredFurniture) { furniture in
                    FurnitureGridItem(furniture: furniture)
                }
            }
            .padding()
        }
    }
}

// MARK: - 生成済みタブ
struct GeneratedTabView: View {
    @StateObject private var modelManager = GeneratedModelManager.shared
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        if modelManager.generatedModels.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("生成済みの家具はありません")
                    .font(.headline)
                    .foregroundColor(.gray)
                
                Text("画像から3D家具を生成してください")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(modelManager.generatedModels) { model in
                        GeneratedModelItem(model: model)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - 生成中タブ
struct GeneratingTabView: View {
    @StateObject private var apiService = MeshyAPIService.shared
    
    var body: some View {
        if apiService.activeTasks.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("生成中の家具はありません")
                    .font(.headline)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(Array(apiService.activeTasks.values).sorted(by: { $0.createdAt > $1.createdAt })) { task in
                        ActiveGenerationTaskRow(task: task)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - 家具グリッドアイテム
struct FurnitureGridItem: View {
    let furniture: FurnitureModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // サムネイル画像
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Image(systemName: "cube.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                )
                .aspectRatio(1, contentMode: .fit)
            
            // 家具名
            Text(furniture.name)
                .font(.headline)
                .lineLimit(1)
            
            // カテゴリとサイズ
            HStack {
                Text(furniture.category.rawValue)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text("\(Int(furniture.realWorldSize.width * 100))×\(Int(furniture.realWorldSize.depth * 100))cm")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - 生成済みモデルアイテム
struct GeneratedModelItem: View {
    let model: GeneratedFurnitureModel
    @StateObject private var modelManager = GeneratedModelManager.shared
    @State private var showingOptions = false
    @State private var thumbnail: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // サムネイル画像
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Group {
                        if let thumbnail = thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "cube.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        }
                    }
                )
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Button(action: {
                        showingOptions = true
                    }) {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
            
            // 家具名
            Text(model.name)
                .font(.headline)
                .lineLimit(1)
            
            // 生成日時
            Text(model.generatedDate, style: .date)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            thumbnail = modelManager.loadThumbnail(for: model)
        }
        .actionSheet(isPresented: $showingOptions) {
            ActionSheet(
                title: Text("オプション"),
                buttons: [
                    .default(Text("名前を変更")) {
                        // TODO: 名前変更処理
                    },
                    .destructive(Text("削除")) {
                        modelManager.deleteModel(model)
                    },
                    .cancel()
                ]
            )
        }
    }
}

// MARK: - アクティブな生成タスク行
struct ActiveGenerationTaskRow: View {
    let task: MeshyTaskData
    @StateObject private var apiService = MeshyAPIService.shared
    
    var body: some View {
        HStack(spacing: 16) {
            // プログレスインジケーター
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: Double(task.progress ?? 0) / 100)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                Text("\(task.progress ?? 0)%")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("モデル生成中")
                    .font(.headline)
                
                Text(task.status.displayName)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                if let startedAt = task.startedAtDate {
                    Text("開始: \(startedAt, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // キャンセルボタン
            Button(action: {
                Task {
                    try? await apiService.cancelTask(taskId: task.id)
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}


#Preview {
    FurnitureManagementView()
}