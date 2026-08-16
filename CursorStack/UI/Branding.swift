import SwiftUI

enum BrandImage {
    static let squareColor = "LogoSquareColor"
    static let fullColor = "LogoFullColor"
    static let fullWhite = "LogoFullWhite"
    static let fullBlack = "LogoFullBlack"
    static let menuBar = "MenuBarIcon"
}

struct BrandMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image(BrandImage.squareColor)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct BrandWordmark: View {
    var height: CGFloat = 44
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(colorScheme == .dark ? BrandImage.fullWhite : BrandImage.fullBlack)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: height)
            .frame(maxWidth: 320, alignment: .leading)
            .accessibilityLabel("CursorStack")
    }
}

struct BrandHero: View {
    var maxWidth: CGFloat = 360

    var body: some View {
        Image(BrandImage.fullColor)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: maxWidth)
            .accessibilityLabel("CursorStack")
    }
}
