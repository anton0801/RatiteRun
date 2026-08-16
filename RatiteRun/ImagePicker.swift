//
//  ImagePicker.swift
//  RatiteRun
//
//  iOS 14-compatible photo picker + a finger drawing/signature canvas.
//

import SwiftUI
import UIKit

// MARK: - Image Picker (UIImagePickerController for iOS 14)

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    var onPicked: (() -> Void)? = nil
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                let resized = image.resized(maxDimension: 1024)
                parent.imageData = resized.jpegData(compressionQuality: 0.8)
                parent.onPicked?()
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - Drawing / signature canvas

struct DrawingCanvas: View {
    @Binding var strokes: [[CGPointCodable]]
    var strokeColor: Color = Palette.action
    var lineWidth: CGFloat = 3
    var background: Color = Palette.bgSoft
    @State private var current: [CGPointCodable] = []

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(background)
            RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1)
            canvasPath(strokes + (current.isEmpty ? [] : [current]))
                .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in current.append(CGPointCodable(v.location)) }
                .onEnded { _ in
                    if !current.isEmpty { strokes.append(current); current = [] }
                }
        )
    }

    private func canvasPath(_ all: [[CGPointCodable]]) -> Path {
        var path = Path()
        for stroke in all {
            guard let first = stroke.first else { continue }
            path.move(to: first.point)
            for p in stroke.dropFirst() { path.addLine(to: p.point) }
        }
        return path
    }
}
