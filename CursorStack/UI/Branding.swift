import SwiftUI

enum BrandImage {
    static let squareColor = "LogoSquareColor"
    static let squareMono = "LogoSquareMono"
    static let fullColor = "LogoFullColor"
    static let fullWhite = "LogoFullWhite"
    static let fullBlack = "LogoFullBlack"
    static let nameColor = "LogoNameColor"
    static let nameMono = "LogoNameMono"
    static let nameWhite = "LogoNameWhite"
    static let nameBlack = "LogoNameBlack"
    static let menuBar = "MenuBarIcon"
}

enum BrandMarkStyle {
    case adaptive
    case color
    case monochrome
}

struct BrandMark: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 64
    var style: BrandMarkStyle = .color

    var body: some View {
        Image(imageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var imageName: String {
        switch style {
        case .adaptive:
            colorScheme == .dark ? BrandImage.squareMono : BrandImage.squareColor
        case .color:
            BrandImage.squareColor
        case .monochrome:
            BrandImage.squareMono
        }
    }
}

struct BrandLockup: View {
    var markSize: CGFloat = 48
    var style: BrandMarkStyle = .color
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            BrandMark(size: markSize, style: style)

            VStack(alignment: .leading, spacing: 2) {
                Text("CursorStack")
                    .font(.system(size: markSize * 0.38, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BrandNameLogo: View {
    @Environment(\.colorScheme) private var colorScheme
    var width: CGFloat = 160
    var style: BrandMarkStyle = .monochrome

    var body: some View {
        Image(imageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: width)
            .accessibilityLabel("CursorStack")
    }

    private var imageName: String {
        switch style {
        case .adaptive:
            colorScheme == .dark ? BrandImage.nameWhite : BrandImage.nameColor
        case .color:
            BrandImage.nameColor
        case .monochrome:
            colorScheme == .dark ? BrandImage.nameWhite : BrandImage.nameBlack
        }
    }
}

struct StackBarBrandMark: View {
    var body: some View {
        BrandNameLogo(width: 96, style: .adaptive)
    }
}
