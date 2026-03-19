import SwiftUI
import UIKit

struct PocketAILogoBackdrop: View {
    private static let backdropImage: UIImage? = loadBackdropImage()

    var body: some View {
        GeometryReader { proxy in
            if let image = Self.backdropImage {
                let side = min(proxy.size.width * 0.92, proxy.size.height * 0.54, 440)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .opacity(0.34)
                    .mask {
                        edgeFadeMask
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -12)
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
    }

    private var edgeFadeMask: some View {
        Rectangle()
            .fill(Color.white)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .blendMode(.destinationOut)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 120)
                .blendMode(.destinationOut)
            }
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 96)
                .blendMode(.destinationOut)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .trailing,
                    endPoint: .leading
                )
                .frame(width: 96)
                .blendMode(.destinationOut)
            }
            .compositingGroup()
    }

    private static func loadBackdropImage() -> UIImage? {
        guard let url = Bundle.main.url(forResource: "background", withExtension: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

#Preview("PocketAI Logo") {
    ZStack {
        AppTheme.backgroundGradient
            .ignoresSafeArea()
        PocketAILogoBackdrop()
    }
}
