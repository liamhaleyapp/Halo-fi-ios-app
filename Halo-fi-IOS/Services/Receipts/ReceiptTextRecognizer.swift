//
//  ReceiptTextRecognizer.swift
//  Halo-fi-IOS
//
//  On-device OCR (Vision VNRecognizeTextRequest). Primary extraction path:
//  private, free, works offline. Returns the recognized lines top-to-bottom
//  for ReceiptOCRParser. PDFs are rasterized (first page) before OCR.
//

import Foundation
import PDFKit
import UIKit
@preconcurrency import Vision

enum ReceiptTextRecognizer {
    /// Recognized text lines, in reading order.
    static func recognizeLines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage ?? image.normalizedCGImage() else { return [] }
        return try await recognizeLines(in: cgImage, orientation: image.cgImagePropertyOrientation)
    }

    static func recognizeLines(in cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            // Vision's request/handler types aren't Sendable, so they are
            // created and used entirely on the background queue; only the
            // continuation crosses the boundary.
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US"]
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results ?? []
                // Sort top-to-bottom (Vision's origin is bottom-left).
                let lines = observations
                    .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
        }
    }

    /// First page of a PDF as an image suitable for OCR and upload.
    static func firstPageImage(pdfData: Data, scale: CGFloat = 2.0) -> UIImage? {
        guard let doc = PDFDocument(data: pdfData), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
}

extension UIImage {
    /// Vision needs the pixel orientation; UIImage carries it separately.
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// CIImage-backed images (e.g. from some pickers) have no cgImage.
    func normalizedCGImage() -> CGImage? {
        if let cg = cgImage { return cg }
        guard let ci = ciImage else { return nil }
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    /// JPEG bytes at a bounded size — what the backend accepts (≤10 MB) and
    /// what Claude can read (HEIC cannot be sent).
    func receiptJPEGData(maxDimension: CGFloat = 2000, quality: CGFloat = 0.85) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1.0
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}
