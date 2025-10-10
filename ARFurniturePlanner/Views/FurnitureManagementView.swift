//
//  FurnitureManagementView.swift
//  ARFurniturePlanner
//
//  Created by 樋川大聖 on 2025/10/10.
//

import SwiftUI
import PhotosUI

struct FurnitureManagementView: View {
    @StateObject private var furnitureRepository = FurnitureRepository()
    @State private var selectedTab = 0
    @State private var showingImageTo3D = false
    @State private var selectedImage: UIImage?
    @State private var isGenerating = false
    @State private var generationProgress: Double = 0
    @State private var showingARView = false
    @State private var searchText = ""
    
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
                    // 画像から3D生成ボタン
                    Button(action: {
                        showingImageTo3D = true
                    }) {
                        HStack {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                            Text("画像から3D家具を生成")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
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
            .sheet(isPresented: $showingImageTo3D) {
                ImageTo3DGenerationView(
                    isPresented: $showingImageTo3D,
                    selectedImage: $selectedImage
                )
            }
            .fullScreenCover(isPresented: $showingARView) {
                ContentView()
            }
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
    @State private var generatedFurniture: [GeneratedFurniture] = [
        // モックデータ
        GeneratedFurniture(
            id: UUID(),
            name: "カスタムチェア1",
            thumbnailImage: "chair_generated_1",
            modelPath: "chair_generated_1.usdz",
            generatedDate: Date(),
            status: .completed
        )
    ]
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        if generatedFurniture.isEmpty {
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
                    ForEach(generatedFurniture) { furniture in
                        GeneratedFurnitureItem(furniture: furniture)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - 生成中タブ
struct GeneratingTabView: View {
    @State private var generatingTasks: [GenerationTask] = []
    
    var body: some View {
        if generatingTasks.isEmpty {
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
                    ForEach(generatingTasks) { task in
                        GenerationTaskRow(task: task)
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

// MARK: - 生成済み家具アイテム
struct GeneratedFurnitureItem: View {
    let furniture: GeneratedFurniture
    @State private var showingOptions = false
    
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
            Text(furniture.name)
                .font(.headline)
                .lineLimit(1)
            
            // 生成日時
            Text(furniture.generatedDate, style: .date)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .actionSheet(isPresented: $showingOptions) {
            ActionSheet(
                title: Text("オプション"),
                buttons: [
                    .default(Text("名前を変更")) {
                        // TODO: 名前変更処理
                    },
                    .destructive(Text("削除")) {
                        // TODO: 削除処理
                    },
                    .cancel()
                ]
            )
        }
    }
}

// MARK: - 生成タスク行
struct GenerationTaskRow: View {
    let task: GenerationTask
    
    var body: some View {
        HStack(spacing: 16) {
            // サムネイル
            if let image = task.sourceImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.name)
                    .font(.headline)
                
                // 進捗バー
                ProgressView(value: task.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                
                HStack {
                    Text(task.statusText)
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text("\(Int(task.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            // キャンセルボタン
            Button(action: {
                // TODO: キャンセル処理
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

// MARK: - データモデル
struct GeneratedFurniture: Identifiable {
    let id: UUID
    var name: String
    let thumbnailImage: String
    let modelPath: String
    let generatedDate: Date
    let status: GenerationStatus
}

struct GenerationTask: Identifiable {
    let id: UUID
    let name: String
    let sourceImage: UIImage?
    let progress: Double
    let statusText: String
    let startTime: Date
}

enum GenerationStatus {
    case generating
    case completed
    case failed
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image as? UIImage
                    }
                }
            }
        }
    }
}

#Preview {
    FurnitureManagementView()
}