//
//  ImageSourcePicker.swift
//  ARFurniturePlanner
//
//  Created by 樋川大聖 on 2025/10/10.
//

import SwiftUI
import UIKit
import PhotosUI
import AVFoundation

struct ImageSourcePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIViewController {
        if sourceType == .camera {
            // カメラが利用可能か確認
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                print("Camera is not available on this device")
                // カメラが使えない場合はフォトライブラリにフォールバック
                var config = PHPickerConfiguration()
                config.filter = .images
                config.selectionLimit = 1
                let picker = PHPickerViewController(configuration: config)
                picker.delegate = context.coordinator
                return picker
            }
            
            let imagePicker = UIImagePickerController()
            imagePicker.sourceType = .camera
            imagePicker.delegate = context.coordinator
            imagePicker.allowsEditing = false
            imagePicker.cameraCaptureMode = .photo
            imagePicker.cameraDevice = .rear
            return imagePicker
        } else {
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        }
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: ImageSourcePicker
        
        init(_ parent: ImageSourcePicker) {
            self.parent = parent
        }
    }
}

// MARK: - UIImagePickerController Delegate
extension ImageSourcePicker.Coordinator: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = info[.originalImage] as? UIImage {
            parent.selectedImage = image
        }
        parent.dismiss()
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        parent.dismiss()
    }
}

// MARK: - PHPickerViewController Delegate
extension ImageSourcePicker.Coordinator: PHPickerViewControllerDelegate {
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

// MARK: - Image Source Selection View
struct ImageSourceSelectionView: View {
    @Binding var isPresented: Bool
    @Binding var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var showCameraPermissionAlert = false
    @State private var showCameraNotAvailableAlert = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("画像を選択")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 40)
                
                Text("3D家具を生成するための画像を選択してください")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 16) {
                    // カメラオプション
                    Button(action: {
                        print("Camera button tapped")
                        checkCameraPermissionAndProceed()
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("写真を撮る")
                                    .font(.headline)
                                Text("カメラで新しい写真を撮影")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // フォトライブラリオプション
                    Button(action: {
                        print("Photo library button tapped")
                        showPhotoLibrary = true
                    }) {
                        HStack {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 24))
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ライブラリから選択")
                                    .font(.headline)
                                Text("既存の写真から選択")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("画像ソース")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImageSourcePicker(selectedImage: $selectedImage, sourceType: .camera)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoLibrary) {
            ImageSourcePicker(selectedImage: $selectedImage, sourceType: .photoLibrary)
                .ignoresSafeArea()
        }
        .alert("カメラへのアクセス", isPresented: $showCameraPermissionAlert) {
            Button("設定を開く") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("カメラを使用するには、設定でカメラへのアクセスを許可してください。")
        }
        .alert("カメラが利用できません", isPresented: $showCameraNotAvailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("このデバイスではカメラを使用できません。シミュレーターを使用している場合は、実機でテストしてください。")
        }
        .onChange(of: selectedImage) { _ in
            if selectedImage != nil {
                isPresented = false
            }
        }
    }
    
    private func checkCameraPermissionAndProceed() {
        // まずカメラが利用可能か確認
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCameraNotAvailableAlert = true
            return
        }
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            print("Camera permission authorized, opening camera...")
            showCamera = true
        case .notDetermined:
            print("Camera permission not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        print("Camera permission granted, opening camera...")
                        self.showCamera = true
                    } else {
                        print("Camera permission denied by user")
                    }
                }
            }
        case .denied, .restricted:
            print("Camera permission denied or restricted")
            showCameraPermissionAlert = true
        @unknown default:
            print("Unknown camera permission status")
            break
        }
    }
}

#Preview {
    ImageSourceSelectionView(
        isPresented: .constant(true),
        selectedImage: .constant(nil)
    )
}