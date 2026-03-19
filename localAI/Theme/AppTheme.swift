import SwiftUI

enum AppTheme {
    // MARK: - Background
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(uiColor: UIColor { trait in
                    if trait.userInterfaceStyle == .dark {
                        return UIColor(red: 0.05, green: 0.05, blue: 0.12, alpha: 1)
                    }
                    return UIColor(red: 0.95, green: 0.96, blue: 0.99, alpha: 1)
                }),
                Color(uiColor: UIColor { trait in
                    if trait.userInterfaceStyle == .dark {
                        return UIColor(red: 0.08, green: 0.06, blue: 0.18, alpha: 1)
                    }
                    return UIColor(red: 0.90, green: 0.93, blue: 0.98, alpha: 1)
                }),
                Color(uiColor: UIColor { trait in
                    if trait.userInterfaceStyle == .dark {
                        return UIColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 1)
                    }
                    return UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1)
                })
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Bubble Colors
    static let userBubbleGradient = LinearGradient(
        colors: [
            Color(red: 0.25, green: 0.42, blue: 0.97),
            Color(red: 0.37, green: 0.34, blue: 0.88)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static var aiBubbleColor: Color {
        Color(uiColor: .secondarySystemBackground).opacity(0.72)
    }

    // MARK: - Text Colors
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary

    // MARK: - Accent
    static let accent = Color(uiColor: .systemBlue)

    // MARK: - Layout
    static let bubbleCornerRadius: CGFloat = 18
    static let inputCornerRadius: CGFloat = 22
    static let contentPadding: CGFloat = 16
}
