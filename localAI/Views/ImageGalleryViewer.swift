import SwiftUI

struct GalleryImageItem: Identifiable {
    let id: String
    let data: Data
}

struct ImageGalleryViewer: View {
    let items: [GalleryImageItem]
    let initialIndex: Int
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    GeometryReader { geometry in
                        if let image = UIImage(data: item.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .background(Color.black)
                        } else {
                            Color.black
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))

            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if items.count > 1 {
                        Text("\(selectedIndex + 1) / \(items.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.black.opacity(0.18))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    }
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            .padding(.horizontal, 16)
            .padding(.top, 18)
        }
        .statusBarHidden()
        .onAppear {
            selectedIndex = min(max(initialIndex, 0), max(items.count - 1, 0))
        }
    }
}

#Preview("图片查看") {
    ImageGalleryViewer(items: [], initialIndex: 0, title: "会话图片")
}
