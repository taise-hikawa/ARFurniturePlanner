# カメラ権限の設定

カメラ機能を使用するには、以下の手順でプロジェクトにカメラ権限を追加してください：

## Xcodeでの設定

1. Xcodeで`ARFurniturePlanner.xcodeproj`を開く
2. プロジェクトナビゲーターで`ARFurniturePlanner`プロジェクトを選択
3. ターゲット`ARFurniturePlanner`を選択
4. **Info**タブを選択
5. **Custom iOS Target Properties**セクションで、新しい行を追加：
   - Key: `NSCameraUsageDescription`
   - Type: `String`
   - Value: `画像から3D家具を生成するために、カメラで写真を撮影します。`

## 代替方法：Info.plistファイルの直接編集

もしプロジェクトにInfo.plistファイルが存在する場合は、以下のコードを追加：

```xml
<key>NSCameraUsageDescription</key>
<string>画像から3D家具を生成するために、カメラで写真を撮影します。</string>
```

## 確認事項

- iOSシミュレーターではカメラは使用できません（フォトライブラリのみ）
- 実機でテストする場合は、カメラ権限が正しく設定されていることを確認してください
- 初回カメラ使用時に権限ダイアログが表示されます

## トラブルシューティング

もしカメラが動作しない場合：
1. デバイスの設定アプリを開く
2. プライバシー → カメラ → ARFurniturePlannerがオンになっているか確認
3. プロジェクトをクリーンビルドして再実行