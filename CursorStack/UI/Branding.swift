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
    case color
    case monochrome
}

struct BrandMark: View {
    var size: CGFloat = 64
    var style: BrandMarkStyle = .color

    var body: some View {
        Image(style == .color ? BrandImage.squareColor : BrandImage.squareMono)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
    var width: CGFloat = 160
    var style: BrandMarkStyle = .monochrome

    var body: some View {
        Image(style == .color ? BrandImage.nameColor : BrandImage.nameMono)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: width)
            .accessibilityLabel("CursorStack")
    }
}

struct StackBarBrandMark: View {
    var body: some View {
        BrandNameLogo(width: 96, style: .color)
    }
}
