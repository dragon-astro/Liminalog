import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct ProfileShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let payload: FriendInvitePayload

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ProfileShareCard(payload: payload)

                Spacer(minLength: 0)
            }
            .padding(18)
            .background(LiminalTheme.canvasGradient)
            .navigationTitle("プロフィールをシェア")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ProfileShareCard: View {
    let payload: FriendInvitePayload

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(payload.displayName)
                    .font(.title2.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(payload.code)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
            }

            InviteQRCodeView(url: payload.url)
                .frame(width: 210, height: 210)

            ShareLink(
                item: payload.url,
                subject: Text("Liminalogのプロフィール"),
                message: Text(payload.shareMessage)
            ) {
                Label("プロフィールを共有", systemImage: "square.and.arrow.up")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LiminalTheme.accent)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(LiminalTheme.surface)
        )
    }
}

private struct InviteQRCodeView: View {
    let url: URL

    var body: some View {
        Group {
            if let image = InviteQRCodeRenderer.image(from: url.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white)
                    )
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LiminalTheme.elevated)
                    .overlay {
                        Image(systemName: "qrcode")
                    }
            }
        }
    }
}

private enum InviteQRCodeRenderer {
    static func image(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
