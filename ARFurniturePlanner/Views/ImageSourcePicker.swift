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
            let imagePicker = UIImagePickerController()
            imagePicker.sourceType = .camera
            imagePicker.delegate = context.coordinator
            imagePicker.allowsEditing = false
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
                        sourceType = .photoLibrary
                        showImagePicker = true
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
        .sheet(isPresented: $showImagePicker) {
            ImageSourcePicker(selectedImage: $selectedImage, sourceType: sourceType)
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
        .onChange(of: selectedImage) { _ in
            if selectedImage != nil {
                isPresented = false
            }
        }
    }
    
    private func checkCameraPermissionAndProceed() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            sourceType = .camera
            showImagePicker = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        sourceType = .camera
                        showImagePicker = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraPermissionAlert = true
        @unknown default:
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