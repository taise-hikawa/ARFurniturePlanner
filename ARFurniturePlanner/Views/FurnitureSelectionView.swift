//
//  FurnitureSelectionView.swift
//  ARFurniturePlanner
//
//  Created by Kiro on 2025/10/09.
//

import SwiftUI

/// 家具選択UIコンポーネント
struct FurnitureSelectionView: View {
    @ObservedObject var arViewManager: ARViewManager
    
    var body: some View {
        VStack(spacing: 12) {
            // 選択中の家具表示
            if let selectedModel = arViewManager.selectedFurnitureModel {
                HStack {
                    Text("選択中: \(selectedModel.name)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.blue.opacity(0.8))
                        )
                    
                    Spacer()
                    
                    // 配置済み家具数表示
                    if arViewManager.getPlacedFurnitureCount() > 0 {
                        Text("配置済み: \(arViewManager.getPlacedFurnitureCount())個")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal)
            }
            
            // 家具選択スクロールビュー
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(arViewManager.furnitureRepository.availableFurniture) { furniture in
                        FurnitureSelectionCard(
                            furniture: furniture,
                            isSelected: arViewManager.selectedFurnitureModel?.id == furniture.id,
                            onTap: {
                                arViewManager.selectFurnitureModel(furniture)
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            // 初期選択（最初のテスト家具を選択）
            if arViewManager.selectedFurnitureModel == nil,
               let firstTestFurniture = arViewManager.furnitureRepository.availableFurniture.first(where: { $0.category == .test }) {
                arViewManager.selectFurnitureModel(firstTestFurniture)
            }
        }
    }
}

/// 家具選択カード
struct FurnitureSelectionCard: View {
    let furniture: FurnitureModel
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // 家具アイコン（サムネイルの代わり）
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? .blue : .gray.opacity(0.3))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: furnitureIcon)
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
                
                // 家具名
                Text(furniture.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 80)
                
                // サイズ情報
                Text(sizeText)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    /// 家具カテゴリに応じたアイコン
    private var furnitureIcon: String {
        switch furniture.category {
        case .sofa:
            return "sofa.fill"
        case .table:
            return "table.furniture.fill"
        case .chair:
            return "chair.fill"
        case .storage:
            return "cabinet.fill"
        case .test:
            switch furniture.id {
            case "test_cube_001":
                return "cube.fill"
            case "test_sphere_001":
                return "circle.fill"
            case "test_table_001":
                return "table.furniture.fill"
            case "test_chair_001":
                return "chair.fill"
            default:
                return "cube.fill"
            }
        }
    }
    
    /// サイズテキスト
    private var sizeText: String {
        let size = furniture.realWorldSize
        return String(format: "%.1f×%.1f×%.1fm", size.width, size.height, size.depth)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            FurnitureSelectionView(arViewManager: ARViewManager())
                .padding()
        }
    }
}