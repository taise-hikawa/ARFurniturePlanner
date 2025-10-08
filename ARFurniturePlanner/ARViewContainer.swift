//
//  ARViewContainer.swift
//  ARFurniturePlanner
//
//  Created by 樋川大聖 on 2025/10/09.
//

import SwiftUI
import ARKit
import RealityKit

/// ARViewをSwiftUIに統合するためのUIViewRepresentable
struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arViewManager: ARViewManager
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // ARViewManagerにARViewを設定
        arViewManager.setARView(arView)
        
        // ARSessionを開始
        arViewManager.startARSession()
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // 必要に応じてARViewの更新処理を実装
    }
    
    static func dismantleUIView(_ uiView: ARView, coordinator: ()) {
        // ARViewが破棄される際のクリーンアップ処理
        uiView.session.pause()
    }
}