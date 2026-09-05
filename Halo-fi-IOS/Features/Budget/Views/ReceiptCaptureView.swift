//
//  ReceiptCaptureView.swift
//  Halo-fi-IOS
//
//  How a receipt gets into the app. Four doors, all VoiceOver-first:
//    Take a photo          — with VoiceOver running: our own camera with
//                             spoken framing cues + Magic Tap = capture;
//                             otherwise VisionKit's document scanner.
//    Someone helped me     — photo library (PhotosPicker); HEIC → JPEG.
//    Choose a file         — PDF or image via the Files app.
//  Every sheet has the Escape gesture wired and moves focus to its heading.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct ReceiptCaptureView: View {
    let onCaptured: (CapturedReceipt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingScanner = false
    @State private var showingAccessibleCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var errorMessage: String?
    @State private var isPreparing = false
    @AccessibilityFocusState private var headingFocused: Bool

    private var useAccessibleCamera: Bool {
        UIAccessibility.isVoiceOverRunning || !VNDocumentCameraViewController.isSupported
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Add a receipt")
                        .font(.title.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)

                    Text("A receipt is the proof Social Security asks for. Any of these works.")
                        .foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }

                    doorButton("Take a photo", icon: "camera.fill",
                               hint: useAccessibleCamera
                               ? "Opens the camera. Halo tells you how to frame the receipt and double-tap with two fingers to capture."
                               : "Opens the document scanner, which finds the edges and captures automatically.") {
                        if useAccessibleCamera { showingAccessibleCamera = true } else { showingScanner = true }
                    }

                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        doorLabel("Someone helped me photograph this", icon: "photo.on.rectangle")
                    }
                    .accessibilityHint("Choose a photo of the receipt from your photo library.")

                    doorButton("Choose a file", icon: "doc.fill",
                               hint: "Pick a PDF or image, for example an emailed receipt you saved to Files.") {
                        showingFileImporter = true
                    }

                    if isPreparing {
                        ProgressView("Preparing…")
                            .accessibilityLabel("Preparing the receipt")
                    }
                }
                .padding(20)
            }
            .readableContentWidth()
            .background(Color.haloBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseToolbarButton(label: "Cancel") { dismiss() }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { headingFocused = true }
            }
            .accessibilityAction(.escape) { dismiss() }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScannerView { result in
                    showingScanner = false
                    switch result {
                    case .success(let image): deliver(image: image)
                    case .failure(let error): errorMessage = error.localizedDescription
                    case .cancelled: break
                    }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showingAccessibleCamera) {
                AccessibleReceiptCameraView { image in
                    showingAccessibleCamera = false
                    if let image { deliver(image: image) }
                }
                .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.pdf, .jpeg, .png, .heic, .image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    deliver(fileURL: url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                isPreparing = true
                Task {
                    defer { isPreparing = false; photoItem = nil }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        deliver(image: image)
                    } else {
                        errorMessage = "Couldn't read that photo. Try another one."
                        UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func doorButton(_ title: String, icon: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { doorLabel(title, icon: icon) }
            .buttonStyle(.plain)
            .accessibilityHint(hint)
    }

    private func doorLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.leading)
            Spacer()
            Image(systemName: "chevron.right").accessibilityHidden(true)
        }
        .foregroundColor(.haloTextPrimary)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }

    private func deliver(image: UIImage) {
        guard let jpeg = image.receiptJPEGData() else {
            errorMessage = "Couldn't prepare that image."
            return
        }
        Haptics.engine.play(.tapCrisp)
        onCaptured(.jpeg(jpeg))
        dismiss()
    }

    private func deliver(fileURL: URL) {
        let secured = fileURL.startAccessingSecurityScopedResource()
        defer { if secured { fileURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: fileURL) else {
            errorMessage = "Couldn't read that file."
            return
        }
        if fileURL.pathExtension.lowercased() == "pdf" {
            guard data.count <= ReceiptService.maxBytes else {
                errorMessage = ReceiptServiceError.tooLarge.errorDescription
                return
            }
            onCaptured(.pdf(data))
            dismiss()
        } else if let image = UIImage(data: data) {
            deliver(image: image)
        } else {
            errorMessage = "That file isn't a photo or a PDF."
        }
    }
}

// MARK: - VisionKit document scanner

enum DocumentScanResult {
    case success(UIImage)
    case failure(Error)
    case cancelled
}

struct DocumentScannerView: UIViewControllerRepresentable {
    let completion: (DocumentScanResult) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: (DocumentScanResult) -> Void
        init(completion: @escaping (DocumentScanResult) -> Void) { self.completion = completion }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { completion(.cancelled); return }
            completion(.success(scan.imageOfPage(at: 0)))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            completion(.cancelled)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            completion(.failure(error))
        }
    }
}
