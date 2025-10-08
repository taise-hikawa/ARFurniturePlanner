# 設計文書

## 概要

AR家具プランナーは、ARKit、RealityKit、SwiftUIを使用したiOSアプリケーションです。ユーザーが実世界の空間に3D家具モデルを配置し、操作できるARエクスペリエンスを提供します。

## アーキテクチャ

### システム全体構成

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   SwiftUI Views │    │  ARView Manager │    │ Furniture Models│
│                 │    │                 │    │                 │
│ - FurnitureUI   │◄──►│ - ARSession     │◄──►│ - USDZ Files    │
│ - ControlPanel  │    │ - PlaneDetection│    │ - Metadata JSON │
│ - Tutorial      │    │ - ModelPlacement│    │ - Thumbnails    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ State Management│    │   RealityKit    │    │ Core Data Store │
│                 │    │                 │    │                 │
│ - AppState      │    │ - Entity System │    │ - Model Cache   │
│ - Selection     │    │ - Gestures      │    │ - User Settings │
│ - UI State      │    │ - Lighting      │    │ - Session Data  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### レイヤー構成

1. **プレゼンテーション層** (SwiftUI)
   - ユーザーインターフェース
   - 家具選択UI
   - コントロールパネル

2. **ビジネスロジック層** (Swift)
   - AR管理
   - モデル操作
   - 状態管理

3. **データ層** (Core Data + File System)
   - 3Dモデルファイル
   - メタデータ
   - ユーザー設定

## コンポーネントと インターフェース

### 1. ARViewManager

ARKitとRealityKitの統合を管理する中核コンポーネント

```swift
class ARViewManager: ObservableObject {
    // ARSession管理
    func startARSession()
    func stopARSession()
    func resetARSession()
    
    // 平面検出
    func enablePlaneDetection()
    func handlePlaneDetection(_ anchor: ARPlaneAnchor)
    
    // モデル配置
    func placeFurniture(at location: SIMD3<Float>, model: FurnitureModel)
    func removeFurniture(entity: ModelEntity)
    func clearAllFurniture()
    
    // ジェスチャー処理
    func setupGestures()
    func handleTap(_ gesture: UITapGestureRecognizer)
    func handleDrag(_ gesture: UIPanGestureRecognizer)
}
```

### 2. FurnitureModel

家具の3Dモデルとメタデータを管理

```swift
struct FurnitureModel: Identifiable, Codable {
    let id: String
    let name: String
    let category: FurnitureCategory
    let modelFileName: String
    let thumbnailFileName: String
    let realWorldSize: SIMD3<Float>
    let defaultScale: Float
    
    // モデル読み込み
    func loadModel() async -> ModelEntity?
    func calculateScale() -> Float
}

enum FurnitureCategory: String, CaseIterable {
    case sofa = "ソファ"
    case table = "テーブル"
    case chair = "椅子"
    case storage = "収納"
}
```

### 3. PlacedFurnitureEntity

配置された家具のエンティティ管理

```swift
class PlacedFurnitureEntity: Entity, HasModel, HasCollision {
    let furnitureModel: FurnitureModel
    var isSelected: Bool = false
    
    // 選択状態管理
    func select()
    func deselect()
    func showHighlight()
    func hideHighlight()
    
    // 変形操作
    func updatePosition(_ position: SIMD3<Float>)
    func updateScale(_ scale: Float)
    func updateRotation(_ rotation: simd_quatf)
}
```

### 4. FurnitureRepository

家具データの管理とキャッシング

```swift
class FurnitureRepository: ObservableObject {
    @Published var availableFurniture: [FurnitureModel] = []
    
    // データ読み込み
    func loadFurnitureDatabase() async
    func loadModel(_ model: FurnitureModel) async -> ModelEntity?
    
    // キャッシュ管理
    func cacheModel(_ entity: ModelEntity, for model: FurnitureModel)
    func getCachedModel(for model: FurnitureModel) -> ModelEntity?
    func clearCache()
}
```

## データモデル

### 家具メタデータ構造

```json
{
  "furniture": [
    {
      "id": "sofa_001",
      "name": "3人掛けソファ",
      "category": "sofa",
      "modelFile": "sofa_3seat.usdz",
      "thumbnail": "sofa_3seat_thumb.jpg",
      "realWorldSize": {
        "width": 2.0,
        "height": 0.8,
        "depth": 0.9
      },
      "defaultScale": 1.0,
      "maxScale": 1.5,
      "minScale": 0.5
    }
  ]
}
```

### ARSession設定

```swift
struct ARConfiguration {
    static func createWorldTrackingConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        configuration.isLightEstimationEnabled = true
        return configuration
    }
}
```

## エラーハンドリング

### エラータイプ定義

```swift
enum ARFurnitureError: LocalizedError {
    case arNotSupported
    case cameraAccessDenied
    case modelLoadingFailed(String)
    case planeDetectionFailed
    case trackingLost
    
    var errorDescription: String? {
        switch self {
        case .arNotSupported:
            return "このデバイスはARをサポートしていません"
        case .cameraAccessDenied:
            return "カメラへのアクセスが必要です"
        case .modelLoadingFailed(let modelName):
            return "モデル '\(modelName)' の読み込みに失敗しました"
        case .planeDetectionFailed:
            return "平面を検出できません。明るい場所で平らな表面を映してください"
        case .trackingLost:
            return "ARトラッキングが失われました。デバイスをゆっくり動かしてください"
        }
    }
}
```

### エラーハンドリング戦略

1. **グレースフルデグラデーション**: 機能が利用できない場合の代替手段
2. **ユーザーフレンドリーメッセージ**: 技術的詳細を隠した分かりやすいエラー表示
3. **自動回復**: 可能な場合は自動的にエラー状態から回復
4. **ログ記録**: デバッグ用の詳細ログ

## テスト戦略

### 単体テスト

```swift
class FurnitureModelTests: XCTestCase {
    func testModelScaleCalculation() {
        // スケール計算の正確性をテスト
    }
    
    func testModelLoading() async {
        // モデル読み込みの成功/失敗をテスト
    }
}

class ARViewManagerTests: XCTestCase {
    func testPlacementLogic() {
        // 配置ロジックをテスト
    }
    
    func testGestureHandling() {
        // ジェスチャー処理をテスト
    }
}
```

### 統合テスト

1. **ARSession統合**: ARKitとRealityKitの連携
2. **UI統合**: SwiftUIとARViewの統合
3. **データ統合**: モデル読み込みと表示の統合

### パフォーマンステスト

1. **フレームレート監視**: 30 FPS以上の維持
2. **メモリ使用量**: メモリリークの検出
3. **モデル読み込み時間**: 3秒以内の読み込み完了

## セキュリティ考慮事項

### プライバシー保護

1. **カメラデータ**: ローカル処理のみ、外部送信なし
2. **位置情報**: ARトラッキングのみに使用
3. **ユーザーデータ**: 最小限のデータ収集

### データ保護

1. **モデルファイル**: アプリバンドル内に格納
2. **ユーザー設定**: Keychainまたはローカルストレージ
3. **キャッシュデータ**: 適切な暗号化

## パフォーマンス最適化

### レンダリング最適化

1. **LOD (Level of Detail)**: 距離に応じたモデル詳細度調整
2. **オクルージョンカリング**: 見えないオブジェクトの描画スキップ
3. **テクスチャ圧縮**: メモリ使用量削減

### メモリ管理

1. **遅延読み込み**: 必要時のみモデル読み込み
2. **キャッシュ管理**: LRU方式でのキャッシュ削除
3. **リソース解放**: 未使用リソースの自動解放

### バッテリー最適化

1. **フレームレート調整**: 必要に応じてFPS制限
2. **バックグラウンド処理**: 最小限に抑制
3. **センサー使用**: 必要最小限のセンサー利用

## 拡張性設計

### 将来の機能拡張

1. **新しい家具カテゴリ**: プラグイン方式での追加
2. **カスタムモデル**: ユーザー独自モデルのインポート
3. **クラウド同期**: 配置データのクラウド保存
4. **マルチユーザーAR**: 複数ユーザーでの共有体験

### API設計

```swift
protocol FurnitureProvider {
    func loadFurniture() async -> [FurnitureModel]
    func loadModel(_ model: FurnitureModel) async -> ModelEntity?
}

protocol ARRenderer {
    func render(_ entities: [Entity])
    func updateLighting(_ estimate: ARLightEstimate)
}
```

この設計により、要件定義書で定義されたすべての機能を実装し、将来の拡張にも対応できる柔軟なアーキテクチャを提供します。