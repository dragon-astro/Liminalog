import SwiftUI
import UIKit

struct ProfileHero: View {
    let displayName: String
    let bio: String
    let imageData: Data?
    let accentColor: Color
    let equippedBadge: ProfileBadgeModel
    let iconFrame: ProfileIconFrameStyle
    let cardStyle: ProfileCardStyle
    var showsActions: Bool = true
    let onEdit: () -> Void
    let onShare: () -> Void

    var body: some View {
        let usesGeneratedArtwork = cardStyle.hasGeneratedArtwork
        let contentHorizontalPadding: CGFloat = usesGeneratedArtwork ? 42 : 18
        let contentTopPadding: CGFloat = usesGeneratedArtwork ? 30 : 28
        let contentBottomPadding: CGFloat = usesGeneratedArtwork ? 36 : 28
        let minCardHeight: CGFloat = usesGeneratedArtwork ? 258 : 196
        let photoSize: CGFloat = usesGeneratedArtwork ? 88 : 92
        let photoOuterSize: CGFloat = photoSize + 16

        HStack(alignment: .top, spacing: usesGeneratedArtwork ? 10 : 14) {
            VStack(spacing: 8) {
                ProfilePhotoView(
                    displayName: displayName,
                    imageData: imageData,
                    accentColor: accentColor,
                    frameStyle: iconFrame,
                    size: photoSize
                )

                if showsActions {
                    HStack(spacing: 9) {
                        ProfileHeroActionButton(systemImage: "pencil", label: "編集", isOnGeneratedArtwork: usesGeneratedArtwork, action: onEdit)
                        ProfileHeroActionButton(systemImage: "square.and.arrow.up", label: "シェア", isOnGeneratedArtwork: usesGeneratedArtwork, action: onShare)
                    }
                    .foregroundStyle(cardStyle.textColor)
                }
            }
            .frame(width: max(photoOuterSize, 78), alignment: .top)

            VStack(alignment: .leading, spacing: 8) {
                Text(displayName)
                    .font(.title2.weight(.bold))
                    .profileGeneratedCardReadableText(enabled: usesGeneratedArtwork, fallback: cardStyle.textColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .padding(.trailing, 4)

                EquippedBadgePill(badge: equippedBadge)
                    .frame(height: 23, alignment: .leading)

                Text(bio.isEmpty ? "プロフィールを育てよう" : bio)
                    .font(.subheadline)
                    .profileGeneratedCardReadableText(enabled: usesGeneratedArtwork, fallback: cardStyle.secondaryTextColor)
                    .lineLimit(2)
                    .frame(minHeight: 42, alignment: .topLeading)
            }
            .padding(.top, usesGeneratedArtwork ? 16 : 0)
            .padding(.trailing, usesGeneratedArtwork ? 20 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.top, contentTopPadding)
        .padding(.bottom, contentBottomPadding)
        .frame(maxWidth: .infinity, minHeight: minCardHeight, alignment: .topLeading)
        .background {
            ProfileDecoratedCardBackground(style: cardStyle, accentColor: accentColor, cornerRadius: 8)
        }
        .padding(.horizontal, usesGeneratedArtwork ? -6 : 0)
        .padding(.top, usesGeneratedArtwork ? 0 : 0)
    }
}

private extension View {
    @ViewBuilder
    func profileGeneratedCardReadableText(enabled: Bool, fallback: Color) -> some View {
        if enabled {
            self
                .foregroundStyle(.white)
                .blendMode(.difference)
        } else {
            self
                .foregroundStyle(fallback)
        }
    }
}

struct ProfileDecoratedCardBackground: View {
    let style: ProfileCardStyle
    let accentColor: Color
    let cornerRadius: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var hasOrnament: Bool {
        style.id != ProfileDecorationUnlocks.noCardStyleID
    }

    var body: some View {
        let usesGeneratedArtwork = style.hasGeneratedArtwork

        ZStack {
            if usesGeneratedArtwork {
                GeometryReader { proxy in
                    Image(style.artworkAssetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(generatedArtworkScale(for: proxy.size))
                        .offset(y: generatedArtworkOffsetY(for: proxy.size))
                        .allowsHitTesting(false)
                }
            } else {
                shape
                    .fill(style.backgroundColor)
                    .overlay {
                        ProfileCardDecorationLayer(style: style, accentColor: accentColor)
                    }
                    .overlay { topSheen }
                    .overlay(alignment: .bottom) {
                        DecorativeAccentStrip(color: style.stripColor(accentColor: accentColor))
                            .clipShape(shape)
                    }
                    .overlay {
                        shape.stroke(style.borderColor(accentColor: accentColor), lineWidth: style.borderWidth)
                    }
                    .clipShape(shape)

                if hasOrnament {
                    ProfileCardBorderOrnament(style: style, accentColor: accentColor, cornerRadius: cornerRadius)
                }
            }
        }
    }

    private func generatedArtworkScale(for size: CGSize) -> CGFloat {
        size.height < 60 ? 1.18 : 1.08
    }

    private func generatedArtworkOffsetY(for size: CGSize) -> CGFloat {
        size.height < 60 ? -2 : -24
    }

    // 上端の控えめな光沢。ダーク地でガラス質の艶を、ライト地ではほぼ不可視に。
    private var topSheen: some View {
        LinearGradient(
            colors: [.white.opacity(0.1), .white.opacity(0)],
            startPoint: .top,
            endPoint: .center
        )
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

/// カードの外周にはみ出す縁取り装飾。標準は同系グラデ＋グロー、
/// 特別カードは二重縁取り＋四隅の珠で豪華に仕上げる。
private struct ProfileCardBorderOrnament: View {
    let style: ProfileCardStyle
    let accentColor: Color
    let cornerRadius: CGFloat

    private var tint: Color { style.markColor(accentColor: accentColor) }
    private var luminous: Color { tint.liminalLuminous }

    // 小さなプレビューでも破綻しないよう張り出し量をスケールする。
    private var inset: CGFloat { cornerRadius >= 6 ? 6 : 3 }
    private var lineWidth: CGFloat { cornerRadius >= 6 ? 2 : 1.5 }
    private var ornamentRadius: CGFloat { cornerRadius + inset }

    private var isLavish: Bool {
        [
            "aurora_panel",
            "kintsugi_panel",
            "prism_dew_panel",
            "snow_crest_panel",
            "chrono_panel",
            "lacquer_panel",
            "horizon_panel"
        ].contains(style.id)
    }

    private var borderGradient: AngularGradient {
        AngularGradient(
            colors: [tint, luminous, tint, luminous, tint],
            center: .center,
            angle: .degrees(-90)
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ornamentRadius, style: .continuous)
        ZStack {
            // 縁取りのグロー。
            shape
                .stroke(tint.opacity(0.6), lineWidth: lineWidth + 2)
                .blur(radius: 6)
                .opacity(0.5)
            // 主縁取り。
            shape
                .stroke(borderGradient, lineWidth: lineWidth)

            if isLavish {
                // 外側の極細ヘアラインで二重縁取りに。
                RoundedRectangle(cornerRadius: ornamentRadius + 3, style: .continuous)
                    .stroke(luminous.opacity(0.5), lineWidth: 1)
                    .padding(-3)
                gem(.topLeading)
                gem(.topTrailing)
                gem(.bottomLeading)
                gem(.bottomTrailing)
            }
        }
        .padding(-inset)
        .allowsHitTesting(false)
    }

    private func gem(_ alignment: Alignment) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(luminous)
            .frame(width: 5, height: 5)
            .rotationEffect(.degrees(45))
            .shadow(color: tint.opacity(0.8), radius: 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

private struct ProfileCardDecorationLayer: View {
    let style: ProfileCardStyle
    let accentColor: Color

    private var tint: Color {
        style.markColor(accentColor: accentColor)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // すべてのカードに共通の twilight グロー。ベタ塗りを避け空気感の土台を敷く（§4）。
                ambientGlow(proxy: proxy)

                switch style.id {
                case "quiet_sky":
                    EmptyView()
                case "cloud_panel":
                    cloudWisps(proxy: proxy)
                case "ripple_panel", "tide_panel":
                    waveLines(proxy: proxy)
                case "leaf_panel", "wisteria_panel", "laurel_panel", "petal_panel", "ember_vine_panel", "horizon_panel":
                    botanicalCorners(proxy: proxy, flowers: ["wisteria_panel", "petal_panel", "horizon_panel"].contains(style.id))
                case "dawn_panel":
                    diagonalWash(proxy: proxy, opacity: 0.18)
                    pollenDots(proxy: proxy)
                case "frost_panel", "porcelain_panel", "snow_crest_panel":
                    frost(proxy: proxy)
                    crystalGrid(proxy: proxy)
                case "thread_panel":
                    wovenLines(proxy: proxy)
                    stitchBorder(proxy: proxy)
                case "chart_panel":
                    chartMarks(proxy: proxy)
                case "chrono_panel":
                    timeline(proxy: proxy)
                    chartMarks(proxy: proxy)
                case "aurora_panel", "prism_dew_panel":
                    aurora(proxy: proxy)
                    pollenDots(proxy: proxy)
                case "kintsugi_panel", "lacquer_panel":
                    kintsugiVeins(proxy: proxy)
                default:
                    sideRail(proxy: proxy, width: 4, opacity: 0.24)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    // 角からにじむ柔らかな放射グロー（上部に主、対角に従）。
    @ViewBuilder
    private func ambientGlow(proxy: GeometryProxy) -> some View {
        Rectangle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(0.16), tint.opacity(0)],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.95
                )
            )
        Rectangle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(0.07), tint.opacity(0)],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.7
                )
            )
    }

    @ViewBuilder
    private func ruledLines(proxy: GeometryProxy, count: Int, opacity: Double) -> some View {
        ForEach(0..<count, id: \.self) { index in
            Rectangle()
                .fill(tint.opacity(opacity))
                .frame(height: 1)
                .offset(y: proxy.size.height * (0.22 + CGFloat(index) * 0.14))
        }
    }

    @ViewBuilder
    private func wovenLines(proxy: GeometryProxy) -> some View {
        ForEach(0..<4, id: \.self) { index in
            Rectangle()
                .fill(tint.opacity(0.1))
                .frame(width: 1)
                .offset(x: proxy.size.width * (-0.3 + CGFloat(index) * 0.2))
        }
        ForEach(0..<3, id: \.self) { index in
            Rectangle()
                .fill(tint.opacity(0.08))
                .frame(height: 1)
                .offset(y: proxy.size.height * (-0.22 + CGFloat(index) * 0.22))
        }
    }

    @ViewBuilder
    private func softCircles(proxy: GeometryProxy) -> some View {
        Circle()
            .fill(tint.opacity(0.14))
            .frame(width: proxy.size.width * 0.56, height: proxy.size.width * 0.56)
            .blur(radius: 10)
            .offset(x: proxy.size.width * 0.28, y: -proxy.size.height * 0.24)
        Circle()
            .stroke(tint.opacity(0.1), lineWidth: 1)
            .frame(width: proxy.size.width * 0.4, height: proxy.size.width * 0.4)
            .offset(x: -proxy.size.width * 0.34, y: proxy.size.height * 0.22)
    }

    @ViewBuilder
    private func cloudWisps(proxy: GeometryProxy) -> some View {
        ForEach(0..<4, id: \.self) { index in
            Circle()
                .trim(from: 0.08, to: 0.42)
                .stroke(tint.liminalLuminous.opacity(0.2 - Double(index) * 0.025), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: proxy.size.width * (0.42 + CGFloat(index) * 0.1), height: proxy.size.width * (0.42 + CGFloat(index) * 0.1))
                .offset(x: proxy.size.width * 0.22, y: -proxy.size.height * 0.34)
                .rotationEffect(.degrees(Double(index) * 10))
        }
        Capsule()
            .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0)], startPoint: .leading, endPoint: .trailing))
            .frame(width: proxy.size.width * 0.5, height: 3)
            .offset(x: -proxy.size.width * 0.18, y: proxy.size.height * 0.28)
            .blur(radius: 2)
    }

    @ViewBuilder
    private func waveLines(proxy: GeometryProxy) -> some View {
        ForEach(0..<4, id: \.self) { index in
            Path { path in
                let y = proxy.size.height * (0.28 + CGFloat(index) * 0.12)
                path.move(to: CGPoint(x: proxy.size.width * 0.04, y: y))
                path.addCurve(
                    to: CGPoint(x: proxy.size.width * 0.96, y: y + CGFloat(index % 2 == 0 ? -7 : 7)),
                    control1: CGPoint(x: proxy.size.width * 0.32, y: y - 18),
                    control2: CGPoint(x: proxy.size.width * 0.66, y: y + 18)
                )
            }
            .stroke(tint.opacity(0.18 - Double(index) * 0.018), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        Circle()
            .stroke(tint.liminalLuminous.opacity(0.18), lineWidth: 1)
            .frame(width: proxy.size.height * 0.6, height: proxy.size.height * 0.6)
            .offset(x: proxy.size.width * 0.34, y: -proxy.size.height * 0.28)
    }

    @ViewBuilder
    private func botanicalCorners(proxy: GeometryProxy, flowers: Bool) -> some View {
        botanicalBranch(proxy: proxy, alignment: .topLeading, mirrored: false, flowers: flowers)
        botanicalBranch(proxy: proxy, alignment: .bottomTrailing, mirrored: true, flowers: flowers)
    }

    private func botanicalBranch(
        proxy: GeometryProxy,
        alignment: Alignment,
        mirrored: Bool,
        flowers: Bool
    ) -> some View {
        ZStack {
            Path { path in
                let start = CGPoint(x: proxy.size.width * 0.12, y: proxy.size.height * 0.2)
                path.move(to: start)
                path.addCurve(
                    to: CGPoint(x: proxy.size.width * 0.52, y: proxy.size.height * 0.1),
                    control1: CGPoint(x: proxy.size.width * 0.22, y: proxy.size.height * 0.02),
                    control2: CGPoint(x: proxy.size.width * 0.38, y: proxy.size.height * 0.04)
                )
            }
            .stroke(tint.opacity(0.32), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            ForEach(0..<4, id: \.self) { index in
                Ellipse()
                    .fill(tint.liminalLuminous.opacity(0.34))
                    .frame(width: 7, height: 14)
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -48 : 48))
                    .offset(x: proxy.size.width * (-0.1 + CGFloat(index) * 0.09), y: proxy.size.height * (-0.03 + CGFloat(index % 2) * 0.05))
            }

            if flowers {
                flower()
                    .frame(width: 18, height: 18)
                    .offset(x: proxy.size.width * 0.16, y: -proxy.size.height * 0.02)
                flower()
                    .frame(width: 13, height: 13)
                    .offset(x: proxy.size.width * 0.36, y: -proxy.size.height * 0.1)
            } else {
                Circle()
                    .fill(tint.liminalLuminous.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .offset(x: proxy.size.width * 0.34, y: -proxy.size.height * 0.08)
            }
        }
        .frame(width: proxy.size.width * 0.55, height: proxy.size.height * 0.38)
        .scaleEffect(x: mirrored ? -1 : 1, y: mirrored ? -1 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(10)
    }

    private func flower() -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                Ellipse()
                    .fill(tint.liminalLuminous.opacity(0.64))
                    .frame(width: 7, height: 12)
                    .offset(y: -5)
                    .rotationEffect(.degrees(Double(index) * 72))
            }
            Circle()
                .fill(Color(hex: "#FFE3A3").opacity(0.8))
                .frame(width: 4, height: 4)
        }
    }

    @ViewBuilder
    private func pollenDots(proxy: GeometryProxy) -> some View {
        ForEach(0..<9, id: \.self) { index in
            Circle()
                .fill(index.isMultiple(of: 3) ? Color(hex: "#FFE3A3").opacity(0.5) : tint.liminalLuminous.opacity(0.42))
                .frame(width: index.isMultiple(of: 3) ? 5 : 3, height: index.isMultiple(of: 3) ? 5 : 3)
                .offset(
                    x: proxy.size.width * (-0.38 + CGFloat(index % 5) * 0.19),
                    y: proxy.size.height * (-0.28 + CGFloat(index / 5) * 0.56)
                )
        }
    }

    @ViewBuilder
    private func crystalGrid(proxy: GeometryProxy) -> some View {
        ForEach(0..<4, id: \.self) { index in
            Rectangle()
                .fill(tint.liminalLuminous.opacity(0.16))
                .frame(width: 1, height: proxy.size.height * 0.4)
                .rotationEffect(.degrees(Double(index) * 45))
                .offset(x: proxy.size.width * 0.32, y: -proxy.size.height * 0.18)
        }
    }

    @ViewBuilder
    private func stitchBorder(proxy: GeometryProxy) -> some View {
        ForEach(0..<9, id: \.self) { index in
            Capsule()
                .fill(tint.liminalLuminous.opacity(0.36))
                .frame(width: 1.5, height: 7)
                .rotationEffect(.degrees(90))
                .offset(x: proxy.size.width * (-0.38 + CGFloat(index) * 0.095), y: -proxy.size.height * 0.36)
        }
        ForEach(0..<9, id: \.self) { index in
            Capsule()
                .fill(tint.opacity(0.28))
                .frame(width: 1.5, height: 7)
                .rotationEffect(.degrees(90))
                .offset(x: proxy.size.width * (-0.38 + CGFloat(index) * 0.095), y: proxy.size.height * 0.36)
        }
    }

    @ViewBuilder
    private func chartMarks(proxy: GeometryProxy) -> some View {
        grid(proxy: proxy, opacity: 0.06)
        Path { path in
            path.move(to: CGPoint(x: proxy.size.width * 0.16, y: proxy.size.height * 0.68))
            path.addCurve(
                to: CGPoint(x: proxy.size.width * 0.86, y: proxy.size.height * 0.28),
                control1: CGPoint(x: proxy.size.width * 0.34, y: proxy.size.height * 0.34),
                control2: CGPoint(x: proxy.size.width * 0.62, y: proxy.size.height * 0.72)
            )
        }
        .stroke(tint.liminalLuminous.opacity(0.45), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        ForEach(0..<4, id: \.self) { index in
            Circle()
                .fill(tint.opacity(0.38))
                .frame(width: 4, height: 4)
                .offset(x: proxy.size.width * (-0.32 + CGFloat(index) * 0.22), y: proxy.size.height * (index.isMultiple(of: 2) ? -0.18 : 0.2))
        }
    }

    @ViewBuilder
    private func kintsugiVeins(proxy: GeometryProxy) -> some View {
        diagonalWash(proxy: proxy, opacity: 0.12)
        ForEach(0..<3, id: \.self) { index in
            Path { path in
                let x = proxy.size.width * (0.18 + CGFloat(index) * 0.24)
                path.move(to: CGPoint(x: x, y: proxy.size.height * 0.04))
                path.addCurve(
                    to: CGPoint(x: x + proxy.size.width * 0.08, y: proxy.size.height * 0.94),
                    control1: CGPoint(x: x - proxy.size.width * 0.1, y: proxy.size.height * 0.32),
                    control2: CGPoint(x: x + proxy.size.width * 0.16, y: proxy.size.height * 0.56)
                )
            }
            .stroke(Color(hex: "#FFE3A3").opacity(index == 1 ? 0.54 : 0.34), style: StrokeStyle(lineWidth: index == 1 ? 1.8 : 1.1, lineCap: .round, lineJoin: .round))
            .shadow(color: tint.opacity(0.3), radius: 2)
        }
    }

    // 端のレールはベタでなく上下フェードのグラデで奥行きを出す。
    @ViewBuilder
    private func sideRail(proxy: GeometryProxy, width: CGFloat, opacity: Double) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [tint.opacity(opacity), tint.opacity(opacity * 0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cornerNotch(proxy: GeometryProxy) -> some View {
        Rectangle()
            .fill(tint.opacity(0.16))
            .frame(width: proxy.size.width * 0.34, height: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 10)
    }

    @ViewBuilder
    private func diagonalWash(proxy: GeometryProxy, opacity: Double) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [tint.opacity(opacity), tint.opacity(0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: proxy.size.width * 0.7, height: proxy.size.height * 1.8)
            .rotationEffect(.degrees(18))
            .offset(x: -proxy.size.width * 0.16)
            .blur(radius: 3)
    }

    @ViewBuilder
    private func shine(proxy: GeometryProxy) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0), .white.opacity(0.26), .white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: proxy.size.width * 0.22, height: proxy.size.height * 1.4)
            .rotationEffect(.degrees(28))
            .offset(x: -proxy.size.width * 0.2)
            .blur(radius: 2)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(tint.opacity(0.18), lineWidth: 1)
            .padding(9)
    }

    @ViewBuilder
    private func leafArc(proxy: GeometryProxy) -> some View {
        Circle()
            .trim(from: 0.08, to: 0.42)
            .stroke(tint.opacity(0.26), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: proxy.size.width * 0.72, height: proxy.size.width * 0.72)
            .offset(x: proxy.size.width * 0.24, y: proxy.size.height * 0.2)
    }

    @ViewBuilder
    private func grid(proxy: GeometryProxy, opacity: Double) -> some View {
        ForEach(0..<4, id: \.self) { index in
            Rectangle()
                .fill(tint.opacity(opacity))
                .frame(width: 1)
                .offset(x: proxy.size.width * (-0.3 + CGFloat(index) * 0.2))
            Rectangle()
                .fill(tint.opacity(opacity))
                .frame(height: 1)
                .offset(y: proxy.size.height * (-0.26 + CGFloat(index) * 0.18))
        }
    }

    @ViewBuilder
    private func timeline(proxy: GeometryProxy) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.26), tint.opacity(0.08)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
            .offset(y: proxy.size.height * 0.12)
        ForEach(0..<3, id: \.self) { index in
            Circle()
                .fill(tint.opacity(0.32))
                .frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.5), radius: 2)
                .offset(x: proxy.size.width * (-0.24 + CGFloat(index) * 0.24), y: proxy.size.height * 0.12)
        }
    }

    @ViewBuilder
    private func sliders(proxy: GeometryProxy) -> some View {
        ForEach(0..<3, id: \.self) { index in
            Capsule()
                .fill(tint.opacity(0.14))
                .frame(width: proxy.size.width * 0.54, height: 2)
                .offset(x: proxy.size.width * 0.1, y: proxy.size.height * (-0.18 + CGFloat(index) * 0.16))
            Circle()
                .fill(tint.opacity(0.32))
                .frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.5), radius: 2)
                .offset(x: proxy.size.width * (-0.02 + CGFloat(index) * 0.08), y: proxy.size.height * (-0.18 + CGFloat(index) * 0.16))
        }
    }

    @ViewBuilder
    private func frost(proxy: GeometryProxy) -> some View {
        ForEach(0..<3, id: \.self) { index in
            Rectangle()
                .fill(tint.opacity(0.16))
                .frame(width: 1, height: proxy.size.height * 0.5)
                .rotationEffect(.degrees(Double(index) * 60))
                .offset(x: proxy.size.width * 0.28, y: -proxy.size.height * 0.14)
        }
    }

    @ViewBuilder
    private func archiveBands(proxy: GeometryProxy) -> some View {
        sideRail(proxy: proxy, width: 6, opacity: 0.26)
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0), tint.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: proxy.size.height * 0.34)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder
    private func focusCorners(proxy: GeometryProxy) -> some View {
        ForEach(0..<4, id: \.self) { index in
            UnevenRoundedRectangle(topLeadingRadius: index == 0 ? 4 : 0, bottomLeadingRadius: index == 2 ? 4 : 0, bottomTrailingRadius: index == 3 ? 4 : 0, topTrailingRadius: index == 1 ? 4 : 0)
                .stroke(tint.opacity(0.32), lineWidth: 1.5)
                .frame(width: 18, height: 18)
                .offset(
                    x: proxy.size.width * (index == 0 || index == 2 ? -0.4 : 0.4),
                    y: proxy.size.height * (index < 2 ? -0.32 : 0.32)
                )
        }
    }

    @ViewBuilder
    private func aurora(proxy: GeometryProxy) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.28), Color(hex: "#D946EF").opacity(0.16), tint.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: proxy.size.height * 0.62)
            .rotationEffect(.degrees(-10))
            .offset(y: -proxy.size.height * 0.08)
            .blur(radius: 6)
    }

    @ViewBuilder
    private func goldTrim(proxy: GeometryProxy) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [tint.opacity(0.5), tint.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.5
            )
            .padding(5)
        Rectangle()
            .fill(tint.opacity(0.16))
            .frame(height: 2)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 10)
    }

    // MARK: 固有カード意匠（代表）

    /// 紙片（低位）— 罫線＋左マージン線＋綴じ穴。ノートの素朴な個性。
    @ViewBuilder
    private func paperRule(proxy: GeometryProxy) -> some View {
        ForEach(0..<5, id: \.self) { index in
            Rectangle()
                .fill(tint.opacity(0.12))
                .frame(height: 1)
                .offset(y: proxy.size.height * (-0.3 + CGFloat(index) * 0.15))
        }
        Rectangle()
            .fill(tint.opacity(0.3))
            .frame(width: 1.5)
            .offset(x: -proxy.size.width * 0.34)
        ForEach(0..<3, id: \.self) { index in
            Circle()
                .fill(tint.opacity(0.2))
                .frame(width: 5, height: 5)
                .offset(x: -proxy.size.width * 0.44, y: proxy.size.height * (-0.22 + CGFloat(index) * 0.22))
        }
    }

    /// 方眼（中位）— 細い方眼＋右肩上がりの折れ線とノード。図表の個性。
    @ViewBuilder
    private func graphPlot(proxy: GeometryProxy) -> some View {
        grid(proxy: proxy, opacity: 0.1)
        let points: [CGPoint] = [
            CGPoint(x: proxy.size.width * 0.12, y: proxy.size.height * 0.72),
            CGPoint(x: proxy.size.width * 0.34, y: proxy.size.height * 0.52),
            CGPoint(x: proxy.size.width * 0.54, y: proxy.size.height * 0.6),
            CGPoint(x: proxy.size.width * 0.74, y: proxy.size.height * 0.34),
            CGPoint(x: proxy.size.width * 0.9, y: proxy.size.height * 0.22)
        ]
        Path { path in
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        .stroke(
            LinearGradient(colors: [tint.opacity(0.55), tint.liminalLuminous], startPoint: .bottomLeading, endPoint: .topTrailing),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
        ForEach(Array(points.enumerated()), id: \.offset) { pair in
            Circle()
                .fill(tint.liminalLuminous)
                .frame(width: 4, height: 4)
                .shadow(color: tint.opacity(0.6), radius: 2)
                .position(pair.element)
        }
    }

    /// 金彩（上位）— 二重金枠＋四隅の鋲＋上辺の小宝石列＋斜めの艶。最も豪華。
    @ViewBuilder
    private func crownOrnate(proxy: GeometryProxy) -> some View {
        let gold = LinearGradient(colors: [tint.liminalLuminous, tint], startPoint: .top, endPoint: .bottom)
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .stroke(gold, lineWidth: 1.5)
            .padding(4)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(tint.opacity(0.32), lineWidth: 1)
            .padding(8)
        cornerStud(.topLeading)
        cornerStud(.topTrailing)
        cornerStud(.bottomLeading)
        cornerStud(.bottomTrailing)
        // 上辺の小宝石列。
        ForEach(0..<5, id: \.self) { index in
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(tint.liminalLuminous)
                .frame(width: 4, height: 4)
                .rotationEffect(.degrees(45))
                .shadow(color: tint.opacity(0.6), radius: 1.5)
                .offset(x: proxy.size.width * (-0.2 + CGFloat(index) * 0.1), y: -proxy.size.height * 0.34)
        }
        // 斜めの艶。
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.16), .white.opacity(0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: proxy.size.width * 0.5, height: proxy.size.height * 1.6)
            .rotationEffect(.degrees(22))
            .offset(x: -proxy.size.width * 0.22)
            .blur(radius: 4)
    }

    private func cornerStud(_ alignment: Alignment) -> some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.6), lineWidth: 1)
                .frame(width: 9, height: 9)
            Circle()
                .fill(tint.liminalLuminous)
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(7)
    }
}

private struct ProfileHeroActionButton: View {
    let systemImage: String
    let label: String
    let isOnGeneratedArtwork: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isOnGeneratedArtwork {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background {
                        Circle()
                            .fill(.black.opacity(0.26))
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.34), lineWidth: 1)
                            }
                    }
                    .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
            } else {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .liminalGlassFill(in: Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct EquippedBadgePill: View {
    let badge: ProfileBadgeModel

    @ViewBuilder
    var body: some View {
        if badge.id != ProfileDecorationUnlocks.noNameBadgeID {
            HStack(spacing: 4) {
                Image(systemName: badge.systemImage)
                    .font(.caption2.weight(.bold))
                Text(badge.title)
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color(hex: badge.tint))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(hex: badge.tint).opacity(0.12), in: Capsule())
            .lineLimit(1)
        }
    }
}

struct ProfilePhotoView: View {
    let displayName: String
    let imageData: Data?
    let accentColor: Color
    let frameStyle: ProfileIconFrameStyle
    let size: CGFloat

    var body: some View {
        let hasFrame = frameStyle.id != ProfileDecorationUnlocks.noIconFrameID

        ZStack {
            Circle()
                .fill(accentColor.gradient)
                .frame(width: size, height: size)

            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }

            Circle()
                .stroke(.white.opacity(0.75), lineWidth: 2)
                .frame(width: size, height: size)

            if hasFrame {
                ProfileIconFrameView(style: frameStyle, accentColor: accentColor, size: size + 16)
            }
        }
        .frame(width: size + 16, height: size + 16)
        .shadow(color: hasFrame ? .black.opacity(0.22) : accentColor.opacity(0.2), radius: hasFrame ? 10 : 14, y: hasFrame ? 8 : 6)
        .shadow(color: hasFrame ? frameStyle.primaryColor.opacity(0.26) : .clear, radius: 12, y: 2)
    }

    private var initial: String {
        String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

struct ProfileIconFrameView: View {
    let style: ProfileIconFrameStyle
    let accentColor: Color
    let size: CGFloat

    // MARK: 描画アーキタイプ
    // 量産バッジ的な「細線＋破線＋浮いた小アイコン＋衝突する2色」をやめ、
    // twilight 世界観（glow・同系グラデ・余白・抑制）に沿った少数の上質な
    // アーキタイプへ集約する。各フレームは色相と1つのジェスチャだけで個性を出す。
    private enum Motif {
        case aura(soft: Bool)                                // 発光する同系グラデの環
        case comet(rotation: Double, length: Double, twin: Bool) // 1筋の流れる弧＋淡い土台環
        case beacon(count: Int, marker: Marker)              // 静かな環＋等間隔の標
        case etched(dash: [CGFloat], innerRing: Bool)        // 上品な点線の環
        case prism                                           // 意図的な薄明スペクトル（特別枠）
    }

    private enum Marker {
        case dot
        case tick
        case gem
    }

    private var primary: Color { style.primaryColor }
    private var secondary: Color { style.secondaryColor }
    private var luminous: Color { style.primaryColor.liminalLuminous }
    private var width: CGFloat { max(style.lineWidth, 2) }
    private var radius: CGFloat { size / 2 }
    private var contentScale: CGFloat { style.hasGeneratedArtwork ? 1.12 : 1.07 }

    /// 同系色のなかで明度だけ動かす発光リング。多色を乱立させない。
    private var ringGradient: AngularGradient {
        AngularGradient(
            colors: [primary, luminous, primary, luminous, primary],
            center: .center,
            angle: .degrees(-90)
        )
    }

    private var softGradient: AngularGradient {
        AngularGradient(
            colors: [primary, secondary, primary],
            center: .center,
            angle: .degrees(-90)
        )
    }

    var body: some View {
        ZStack {
            if style.id != ProfileDecorationUnlocks.noIconFrameID {
                if style.hasGeneratedArtwork {
                    Image(style.artworkAssetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .scaleEffect(contentScale)
                        .allowsHitTesting(false)
                } else if let tier = ProfileIconFrameCatalog.earnedTier(for: style.id) {
                    // 生成PNGが未投入の獲得フレームだけ、開発中fallbackとして描く。
                    EarnedEmblemFrame(tier: tier, tint: primary, accent: secondary, size: size)
                        .allowsHitTesting(false)
                } else {
                    ZStack {
                        glow
                        content
                    }
                    .scaleEffect(contentScale)
                }
            }
        }
        .frame(width: size, height: size)
    }

    // 控えめな単層グロー（暗地での視認性の下支えのみ。装飾は形で担う）。
    private var glow: some View {
        Circle()
            .stroke(primary.opacity(0.4), lineWidth: width + 3)
            .blur(radius: 6)
            .opacity(0.38)
    }

    @ViewBuilder
    private var content: some View {
        // 各フレームは固有のベクター意匠を持つ（段階移行中。未対応idは従来アーキタイプ）。
        switch style.id {
        case "clear_air", "cloud_veil":
            cloudFrame()
        case "ripple_ring", "tideglass_ring":
            rippleFrame()
        case "leaf_orbit", "wisteria_loop", "laurel_light", "petal_wreath", "ember_vine", "horizon_wreath":
            botanicalFrame(flowers: ["petal_wreath", "horizon_wreath", "wisteria_loop"].contains(style.id))
        case "dawn_pollen", "aurora_wreath", "prism_dew":
            luminousPollenFrame()
        case "frost_bloom", "porcelain_halo", "snow_crest":
            crystalFrame()
        case "thread_arc":
            stitchedFrame()
        case "astro_chart", "chrono_orbit":
            orbitChartFrame(ticks: style.id == "chrono_orbit" ? 24 : 12)
        case "kintsugi_ring", "lacquer_vein":
            kintsugiFrame()
        case "signal":
            SignalFrameShape(primary: primary, luminous: luminous, secondary: secondary, width: width, radius: radius)
        case "compass":
            CompassFrameShape(primary: primary, luminous: luminous, secondary: secondary, width: width, radius: radius)
        case "tsukishiro":
            TsukishiroFrameShape(primary: primary, luminous: luminous, secondary: secondary, width: width, radius: radius)
        default:
            archetypeContent
        }
    }

    @ViewBuilder
    private func cloudFrame() -> some View {
        Circle()
            .stroke(primary.opacity(0.18), lineWidth: width)
        Circle()
            .trim(from: 0.58, to: 0.96)
            .stroke(
                LinearGradient(colors: [primary.opacity(0.05), luminous, secondary.opacity(0.75)], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: width + 0.5, lineCap: .round)
            )
            .rotationEffect(.degrees(-18))
        ForEach(0..<4, id: \.self) { index in
            Circle()
                .stroke(luminous.opacity(0.18 - Double(index) * 0.03), lineWidth: 1)
                .frame(width: radius * (0.76 + CGFloat(index) * 0.18), height: radius * (0.76 + CGFloat(index) * 0.18))
                .offset(x: radius * 0.2, y: -radius * 0.46)
        }
        accentDot(angle: -42, scale: 0.85)
        accentDot(angle: 42, scale: 0.58)
    }

    @ViewBuilder
    private func rippleFrame() -> some View {
        ForEach(0..<3, id: \.self) { index in
            Circle()
                .trim(from: 0.05 + Double(index) * 0.08, to: 0.72 - Double(index) * 0.04)
                .stroke(
                    index == 1 ? secondary.opacity(0.72) : primary.opacity(0.62),
                    style: StrokeStyle(lineWidth: max(1.3, width - CGFloat(index) * 0.45), lineCap: .round)
                )
                .scaleEffect(1 - CGFloat(index) * 0.08)
                .rotationEffect(.degrees(Double(index) * 48 - 18))
        }
        ForEach(0..<5, id: \.self) { index in
            accentDot(angle: Double(index) * 48 + 18, scale: index.isMultiple(of: 2) ? 0.62 : 0.38)
        }
    }

    @ViewBuilder
    private func botanicalFrame(flowers: Bool) -> some View {
        Circle()
            .stroke(primary.opacity(0.22), lineWidth: max(1.4, width - 1))
        Circle()
            .trim(from: 0.54, to: 0.95)
            .stroke(ringGradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .rotationEffect(.degrees(-12))
        Circle()
            .trim(from: 0.06, to: 0.38)
            .stroke(secondary.opacity(0.66), style: StrokeStyle(lineWidth: max(1.4, width - 0.7), lineCap: .round))
            .rotationEffect(.degrees(14))
        ForEach(0..<6, id: \.self) { index in
            leaf(angle: -132 + Double(index) * 22, side: index.isMultiple(of: 2) ? -1 : 1)
        }
        ForEach(0..<6, id: \.self) { index in
            leaf(angle: 42 + Double(index) * 20, side: index.isMultiple(of: 2) ? 1 : -1)
        }
        if flowers {
            blossom(angle: -82, scale: 0.78)
            blossom(angle: 118, scale: 0.64)
        } else {
            accentDot(angle: -72, scale: 0.72)
            accentDot(angle: 122, scale: 0.52)
        }
    }

    @ViewBuilder
    private func luminousPollenFrame() -> some View {
        Circle()
            .stroke(
                AngularGradient(colors: [primary, secondary, Color(hex: "#FFE3A3"), primary], center: .center),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
        Circle()
            .stroke(luminous.opacity(0.28), lineWidth: 1)
            .scaleEffect(0.86)
        ForEach(0..<10, id: \.self) { index in
            accentDot(angle: Double(index) * 36 + (index.isMultiple(of: 2) ? 8 : -7), scale: index.isMultiple(of: 3) ? 0.74 : 0.42)
        }
        Circle()
            .trim(from: 0.72, to: 0.98)
            .stroke(secondary.opacity(0.72), style: StrokeStyle(lineWidth: width + 1.2, lineCap: .round))
            .rotationEffect(.degrees(-24))
            .blur(radius: 1.2)
    }

    @ViewBuilder
    private func crystalFrame() -> some View {
        Circle()
            .stroke(ringGradient, lineWidth: width)
        Circle()
            .stroke(luminous.opacity(0.32), lineWidth: 1)
            .scaleEffect(0.82)
        ForEach(0..<8, id: \.self) { index in
            Capsule()
                .fill(index.isMultiple(of: 2) ? luminous : primary.opacity(0.72))
                .frame(width: 1.2, height: index.isMultiple(of: 2) ? width * 3.6 : width * 2.2)
                .offset(y: -radius + width * 0.9)
                .rotationEffect(.degrees(Double(index) * 45))
        }
        ForEach([0, 2, 4, 6], id: \.self) { index in
            FourPointStar(waist: 0.22)
                .fill(luminous.opacity(0.88))
                .frame(width: width + 5, height: width + 5)
                .offset(y: -radius + 1)
                .rotationEffect(.degrees(Double(index) * 45))
        }
    }

    @ViewBuilder
    private func stitchedFrame() -> some View {
        Circle()
            .stroke(primary.opacity(0.18), lineWidth: width + 2)
        Circle()
            .stroke(
                ringGradient,
                style: StrokeStyle(lineWidth: max(1.6, width - 0.4), lineCap: .round, dash: [2, 7])
            )
        ForEach(0..<18, id: \.self) { index in
            Capsule()
                .fill(index.isMultiple(of: 2) ? luminous.opacity(0.75) : secondary.opacity(0.64))
                .frame(width: 1.1, height: width * 2)
                .offset(y: -radius + width * 0.4)
                .rotationEffect(.degrees(Double(index) * 20))
        }
    }

    @ViewBuilder
    private func orbitChartFrame(ticks: Int) -> some View {
        Circle()
            .stroke(primary.opacity(0.22), lineWidth: width)
        Circle()
            .stroke(ringGradient, style: StrokeStyle(lineWidth: max(1.4, width - 0.4), lineCap: .round, dash: [9, 7]))
            .scaleEffect(0.96)
        Circle()
            .trim(from: 0.08, to: 0.56)
            .stroke(secondary.opacity(0.72), style: StrokeStyle(lineWidth: width, lineCap: .round))
            .rotationEffect(.degrees(-34))
        ForEach(0..<ticks, id: \.self) { index in
            Capsule()
                .fill(primary.opacity(index % 6 == 0 ? 0.76 : 0.38))
                .frame(width: 1, height: index % 6 == 0 ? 7 : 3)
                .offset(y: -radius + 1)
                .rotationEffect(.degrees(Double(index) / Double(ticks) * 360))
        }
        ForEach(0..<4, id: \.self) { index in
            accentDot(angle: Double(index) * 83 + 18, scale: index == 0 ? 0.78 : 0.48)
        }
    }

    @ViewBuilder
    private func kintsugiFrame() -> some View {
        Circle()
            .stroke(primary.opacity(0.3), lineWidth: width + 1)
        Circle()
            .stroke(luminous.opacity(0.34), lineWidth: 1)
            .scaleEffect(0.86)
        ForEach(0..<4, id: \.self) { index in
            Path { path in
                path.move(to: CGPoint(x: radius, y: radius * 0.08))
                path.addCurve(
                    to: CGPoint(x: radius * 1.08, y: radius * 0.92),
                    control1: CGPoint(x: radius * 0.78, y: radius * 0.36),
                    control2: CGPoint(x: radius * 1.22, y: radius * 0.58)
                )
                path.addCurve(
                    to: CGPoint(x: radius * 0.92, y: radius * 1.86),
                    control1: CGPoint(x: radius * 0.9, y: radius * 1.18),
                    control2: CGPoint(x: radius * 1.14, y: radius * 1.52)
                )
            }
            .stroke(luminous, style: StrokeStyle(lineWidth: index == 0 ? 1.8 : 1.1, lineCap: .round, lineJoin: .round))
            .rotationEffect(.degrees(Double(index) * 82 + 12))
            .shadow(color: primary.opacity(0.55), radius: 2)
        }
    }

    @ViewBuilder
    private func accentDot(angle: Double, scale: CGFloat) -> some View {
        Circle()
            .fill(luminous)
            .frame(width: (width + 2) * scale, height: (width + 2) * scale)
            .shadow(color: primary.opacity(0.7), radius: 3)
            .offset(y: -radius)
            .rotationEffect(.degrees(angle))
    }

    @ViewBuilder
    private func leaf(angle: Double, side: CGFloat) -> some View {
        Ellipse()
            .fill(LinearGradient(colors: [luminous.opacity(0.86), primary.opacity(0.72)], startPoint: .top, endPoint: .bottom))
            .frame(width: width * 2.8, height: width * 5)
            .rotationEffect(.degrees(side > 0 ? 34 : -34))
            .offset(x: side * width * 1.4, y: -radius + width * 2.5)
            .rotationEffect(.degrees(angle))
            .shadow(color: primary.opacity(0.35), radius: 1.5)
    }

    @ViewBuilder
    private func blossom(angle: Double, scale: CGFloat) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                Ellipse()
                    .fill(LinearGradient(colors: [luminous, secondary.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                    .frame(width: width * 2.4 * scale, height: width * 4.2 * scale)
                    .offset(y: -width * 1.5 * scale)
                    .rotationEffect(.degrees(Double(index) * 72))
            }
            Circle()
                .fill(Color(hex: "#FFE3A3"))
                .frame(width: width * 1.2 * scale, height: width * 1.2 * scale)
        }
        .offset(y: -radius)
        .rotationEffect(.degrees(angle))
        .shadow(color: primary.opacity(0.42), radius: 3)
    }

    @ViewBuilder
    private var archetypeContent: some View {
        switch motif {
        case let .aura(soft):
            auraRing(soft: soft)
        case let .comet(rotation, length, twin):
            cometRing(rotation: rotation, length: length, twin: twin)
        case let .beacon(count, marker):
            beaconRing(count: count, marker: marker)
        case let .etched(dash, innerRing):
            etchedRing(dash: dash, innerRing: innerRing)
        case .prism:
            prismRing()
        }
    }

    // MARK: アーキタイプ実装

    @ViewBuilder
    private func auraRing(soft: Bool) -> some View {
        // 主環＋内外の極細リングの三重構成で奥行きと豪華さを出す。
        Circle()
            .stroke(luminous.opacity(soft ? 0.24 : 0.42), lineWidth: 1)
            .scaleEffect(1.04)
        Circle()
            .stroke(
                soft ? AnyShapeStyle(softGradient) : AnyShapeStyle(ringGradient),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
        Circle()
            .stroke(luminous.opacity(soft ? 0.18 : 0.32), lineWidth: 1)
            .scaleEffect(0.88)
    }

    @ViewBuilder
    private func cometRing(rotation: Double, length: Double, twin: Bool) -> some View {
        // 控えめな土台環。
        Circle()
            .stroke(primary.opacity(0.26), lineWidth: width)
        // 流れる弧（グロー → 本体の2枚重ねで奥行き）。
        cometArc(length: length)
            .blur(radius: 4)
            .opacity(0.7)
            .rotationEffect(.degrees(rotation))
        cometArc(length: length)
            .rotationEffect(.degrees(rotation))
        // コメットヘッド（弧の先端の発光する珠）。
        // Circle の trim は3時方向起点・時計回りのため、上(12時)基準では +90° 補正する。
        cometHead
            .offset(y: -radius)
            .rotationEffect(.degrees(rotation + 90 + length * 360))
        if twin {
            cometArc(length: length * 0.7)
                .opacity(0.55)
                .rotationEffect(.degrees(rotation + 180))
            cometHead
                .offset(y: -radius)
                .rotationEffect(.degrees(rotation + 180 + 90 + length * 0.7 * 360))
                .opacity(0.7)
        }
    }

    private var cometHead: some View {
        Circle()
            .fill(luminous)
            .frame(width: width + 3, height: width + 3)
            .shadow(color: primary.opacity(0.85), radius: 4)
    }

    private func cometArc(length: Double) -> some View {
        Circle()
            .trim(from: 0, to: length)
            .stroke(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: primary.opacity(0), location: 0),
                        .init(color: primary, location: length * 0.55),
                        .init(color: luminous, location: length)
                    ]),
                    center: .center,
                    angle: .degrees(-90)
                ),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
    }

    @ViewBuilder
    private func beaconRing(count: Int, marker: Marker) -> some View {
        Circle()
            .stroke(ringGradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
        Circle()
            .stroke(luminous.opacity(0.22), lineWidth: 1)
            .scaleEffect(0.84)
        ForEach(0..<count, id: \.self) { index in
            markerView(marker)
                .offset(y: -radius)
                .rotationEffect(.degrees(Double(index) / Double(count) * 360))
        }
    }

    @ViewBuilder
    private func markerView(_ marker: Marker) -> some View {
        switch marker {
        case .dot:
            Circle()
                .fill(luminous)
                .frame(width: width + 2, height: width + 2)
                .shadow(color: primary.opacity(0.7), radius: 3)
        case .tick:
            Capsule()
                .fill(LinearGradient(colors: [luminous, primary], startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: width * 2.6)
                .shadow(color: primary.opacity(0.6), radius: 2)
        case .gem:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(luminous)
                .frame(width: width + 3, height: width + 3)
                .rotationEffect(.degrees(45))
                .shadow(color: primary.opacity(0.7), radius: 3)
        }
    }

    @ViewBuilder
    private func etchedRing(dash: [CGFloat], innerRing: Bool) -> some View {
        // 点線の下に淡い連続環を敷き、彫金のような奥行きを出す。
        Circle()
            .stroke(primary.opacity(0.16), lineWidth: width)
        Circle()
            .stroke(
                ringGradient,
                style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash)
            )
        if innerRing {
            Circle()
                .stroke(luminous.opacity(0.4), lineWidth: 1)
                .scaleEffect(0.84)
        }
    }

    @ViewBuilder
    private func prismRing() -> some View {
        // 特別枠のみ、意図的な薄明スペクトルを許容（§2.4 の例外）。
        let spectrum = AngularGradient(
            colors: [primary, secondary, Color(hex: "#FFE3A3"), luminous, primary],
            center: .center
        )
        // スペクトルのグロー層で華やかさを増す。
        Circle()
            .stroke(spectrum, lineWidth: width + 2)
            .blur(radius: 5)
            .opacity(0.6)
        Circle()
            .stroke(spectrum, style: StrokeStyle(lineWidth: width, lineCap: .round))
        Circle()
            .stroke(.white.opacity(0.35), lineWidth: 1)
            .scaleEffect(0.88)
    }

    // MARK: フレームID → アーキタイプの対応（色アイデンティティは catalog 側で維持）
    private var motif: Motif {
        switch style.id {
        case "halo", "tsukishiro", "deep_work":
            return .aura(soft: false)
        case "oboro_edge", "glassline":
            return .aura(soft: true)
        case "signal":
            return .comet(rotation: -30, length: 0.3, twin: true)
        case "orbit":
            return .comet(rotation: 40, length: 0.6, twin: false)
        case "pulse":
            return .comet(rotation: 120, length: 0.52, twin: false)
        case "akatsuki_edge":
            return .comet(rotation: 150, length: 0.44, twin: false)
        case "meridian":
            return .beacon(count: 2, marker: .tick)
        case "focus":
            return .beacon(count: 4, marker: .tick)
        case "compass":
            return .beacon(count: 4, marker: .dot)
        case "vertex":
            return .beacon(count: 4, marker: .gem)
        case "crownline":
            return .beacon(count: 1, marker: .gem)
        case "long_run":
            return .beacon(count: 12, marker: .tick)
        case "quiet_gold":
            return .etched(dash: [3, 9], innerRing: false)
        case "gridline":
            return .etched(dash: [2, 5], innerRing: false)
        case "archive":
            return .etched(dash: [11, 5], innerRing: true)
        case "relic":
            return .etched(dash: [5, 5], innerRing: true)
        case "prism", "aurora_edge":
            return .prism
        default:
            return .aura(soft: false)
        }
    }
}

// MARK: - 獲得勲章フレーム（パラメトリック・ベクター）

/// 継続で得る獲得フレームを「現代的な達成メダル」として描くパラメトリック勲章。
/// プレミアム（自然/作品の生成アート）と種類を分け、見た瞬間「買えない＝勝ち取った」と
/// 分かる金属の報酬語彙にする。品質ラダーは底上げ済み（最低位でも白金のベベル環）：
/// - T1：磨いた白金のベベル環＋細い刻線＋小さなクレスト宝石（質素だが安っぽくない）
/// - T2：暖白金＋月桂の芽＋クレスト拡大
/// - T3：薄金＋月桂（半周）＋面取りクレスト＋多重刻線
/// - T4：豪奢な金メダリオン＋ほぼ全周の金月桂＋放射光＋強い署名グロー（自慢の頂点）
///
/// 金属＝ティア（達成度）の signal。tint（アイテム固有色）はクレスト宝石として残し、
/// 個体識別を保つ（docs/16 §7）。落差そのものが報酬（docs/16 §5・§11）。
struct EarnedEmblemFrame: View {
    let tier: Int            // 1...4
    let tint: Color          // アイテム固有色（クレスト宝石＝個体識別）
    let accent: Color        // secondary（淡い補助光）
    let size: CGFloat

    private var t: Int { min(max(tier, 1), 4) }
    private var luminous: Color { tint.liminalLuminous }
    private var compact: Bool { size < 44 }   // 友達リスト等の小サイズは簡略化＋負荷軽減
    private var unit: CGFloat { size / 108 }  // 96〜108基準で設計、サイズに比例

    private let amber = Color(hex: "#FFE3A3")

    // MARK: ティア・パラメータ（落差を保証する変数群・底上げ済み）
    private var rimWidth: CGFloat { [3.6, 4.3, 5.0, 5.9][t - 1] * unit }
    private var guilloche: Int { [1, 2, 2, 3][t - 1] }          // 内側の細い刻線リング
    private var tickCount: Int { [48, 56, 64, 72][t - 1] }       // 細かい刻み（低コントラスト）
    private var laurelPerSide: Int { [4, 6, 8, 11][t - 1] }
    private var laurelSpan: Double { [56, 78, 100, 124][t - 1] } // 月桂が覆う片側の角度
    private var glowOpacity: Double { [0.12, 0.16, 0.22, 0.30][t - 1] }   // 抑制（金属を主役に）
    private var doubleBand: Bool { t >= 2 }                      // 内側にもう一本＝コイン縁の高級感
    private var hasRays: Bool { t == 4 }
    private var warm: Bool { t >= 3 }                            // 金寄り

    /// 磨いた金属の艶（白金→暖白金→薄金→豪奢な金）。AngularGradient で回り込む光沢。
    private var metal: AngularGradient {
        let stops: [Color]
        switch t {
        case 1: stops = ["#9AA6BC", "#EAF1FB", "#B6C3D8", "#FFFFFF", "#9AA6BC"].map { Color(hex: $0) }
        case 2: stops = ["#A6A6B2", "#F3ECE0", "#CFC9BE", "#FFFFFF", "#A6A6B2"].map { Color(hex: $0) }
        case 3: stops = ["#B89A5A", "#FBEEC8", "#D9BE78", "#FFF8E4", "#C2A668"].map { Color(hex: $0) }
        default: stops = ["#A9772A", "#FFE6A6", "#E4B458", "#FFF7DC", "#B98430"].map { Color(hex: $0) }
        }
        return AngularGradient(colors: stops, center: .center, angle: .degrees(-90))
    }

    /// 刻線・台座などのソリッド差し色。
    private var accentMetal: Color {
        switch t {
        case 1: return Color(hex: "#DCE6F5")
        case 2: return Color(hex: "#EFE6D6")
        case 3: return Color(hex: "#E7C97E")
        default: return Color(hex: "#F4CE7A")
        }
    }

    // 環はアバター外周近くまで広げる（クレスト/月桂は環の上に乗るので外余白は最小）
    private var inset: CGFloat { rimWidth * 0.7 + 2 * unit }
    private var ring: CGFloat { size - inset * 2 }   // メダリオン環の直径
    private var rr: CGFloat { ring / 2 }              // 環の半径

    var body: some View {
        ZStack {
            glowLayer
            if hasRays && !compact { raysLayer }
            guillocheLayer
            if !compact { engravingTicks }
            band                       // ベベル金属環
            if !compact { laurelWreath }
            crest                      // 頂点クレスト宝石（固有色）
        }
        .frame(width: size, height: size)
    }

    // MARK: 下支えグロー（tint）— 金属を twilight 世界に留める。薄く・締まりよく。
    private var glowLayer: some View {
        Circle()
            .stroke(tint.opacity(glowOpacity), lineWidth: rimWidth + 2 * unit)
            .frame(width: ring, height: ring)
            .blur(radius: 4 * unit)
    }

    // MARK: 放射光（T4のみ・儀礼的な後光）
    private var raysLayer: some View {
        ForEach(0..<16, id: \.self) { i in
            Capsule()
                .fill(amber.opacity(i.isMultiple(of: 2) ? 0.30 : 0.14))
                .frame(width: 1.4 * unit, height: rr * 0.55)
                .offset(y: -rr * 0.7)
                .rotationEffect(.degrees(Double(i) / 16 * 360))
        }
        .blur(radius: 0.6)
    }

    // MARK: 内側の細い刻線（guilloché 風の同心リング）
    private var guillocheLayer: some View {
        ForEach(0..<guilloche, id: \.self) { i in
            Circle()
                .stroke((warm ? amber : Color.white).opacity(0.22 - Double(i) * 0.05), lineWidth: 0.8 * unit)
                .frame(width: ring - rimWidth * (2.2 + CGFloat(i) * 1.6),
                       height: ring - rimWidth * (2.2 + CGFloat(i) * 1.6))
        }
    }

    // MARK: 細かい刻み（低コントラストの彫り・計器っぽさを出さない）
    private var engravingTicks: some View {
        ForEach(0..<tickCount, id: \.self) { i in
            Rectangle()
                .fill(accentMetal.opacity(0.5))
                .frame(width: 0.7 * unit, height: rimWidth * 0.7)
                .offset(y: -rr)
                .rotationEffect(.degrees(Double(i) / Double(tickCount) * 360))
        }
        .mask(
            // 上のクレスト位置と下の月桂位置は刻みを抜いて整理する
            Circle().frame(width: ring + rimWidth, height: ring + rimWidth)
        )
    }

    // MARK: ベベル金属環（外影＋本体＋内ハイライトの三層で立体に）
    private var band: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.22), lineWidth: rimWidth + 1.2 * unit)
                .frame(width: ring, height: ring)
                .blur(radius: 0.6)
            Circle()
                .stroke(metal, lineWidth: rimWidth)
                .frame(width: ring, height: ring)
            Circle()
                .stroke(Color.white.opacity(0.6), lineWidth: 0.7 * unit)
                .frame(width: ring - rimWidth + 0.7 * unit, height: ring - rimWidth + 0.7 * unit)
            // 内側にもう一本の細い金属環＝コインの縁取り（T2+の高級感）
            if doubleBand {
                Circle()
                    .stroke(metal, lineWidth: max(1, rimWidth * 0.32))
                    .frame(width: ring - rimWidth * 2.4, height: ring - rimWidth * 2.4)
            }
        }
    }

    // MARK: 月桂冠（接線方向に寝かせた葉が両側から立ち上がる）
    private var laurelWreath: some View {
        ZStack {
            // 枝（底部の弧）
            Circle()
                .trim(from: 0.25 - laurelSpan / 720, to: 0.25 + laurelSpan / 720)
                .stroke(metal, style: StrokeStyle(lineWidth: 1.2 * unit, lineCap: .round))
                .frame(width: ring, height: ring)
            ForEach(0..<laurelPerSide, id: \.self) { i in
                let frac = laurelPerSide <= 1 ? 0 : Double(i) / Double(laurelPerSide - 1)
                let a = 12 + frac * laurelSpan
                let scale = CGFloat(1 - frac * 0.4)
                laurelLeaf(angle: 180 - a, side: -1, scale: scale)
                laurelLeaf(angle: 180 + a, side: 1, scale: scale)
            }
        }
    }

    private func laurelLeaf(angle: Double, side: CGFloat, scale: CGFloat) -> some View {
        let w: CGFloat = rimWidth * 1.0 * scale
        let h: CGFloat = rimWidth * 2.4 * scale
        return Capsule()
            .fill(metal)
            .frame(width: w, height: h)
            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.5 * unit))
            // 接線方向へ寝かせ、内側上向きに開く（放射状の棘にしない）
            .rotationEffect(.degrees(Double(side) * -72))
            .offset(y: -rr)
            .rotationEffect(.degrees(angle))
            .shadow(color: (warm ? amber : Color.white).opacity(0.3), radius: unit)
    }

    // MARK: 頂点クレスト（金属台座＋固有色の面取り宝石）
    private var crest: some View {
        ZStack {
            // 台座（金属のひし形＝宝石のセッティング）
            FourPointStar(waist: 0.42)
                .fill(metal)
                .frame(width: rimWidth * 3.4, height: rimWidth * 3.4)
                .shadow(color: Color.black.opacity(0.25), radius: 1)
            // 宝石本体（固有色・面取り風）
            Circle()
                .fill(RadialGradient(colors: [Color.white, luminous, tint],
                                     center: .init(x: 0.38, y: 0.34),
                                     startRadius: 0, endRadius: rimWidth * 1.5))
                .frame(width: rimWidth * 2.0, height: rimWidth * 2.0)
                .overlay(Circle().stroke(accentMetal, lineWidth: 0.8 * unit))
                .shadow(color: tint.opacity(0.9), radius: 3 * unit)
            // T3+ は宝石脇に小粒の副石
            if t >= 3 {
                ForEach([-1.0, 1.0], id: \.self) { s in
                    Circle()
                        .fill(luminous)
                        .frame(width: rimWidth * 0.8, height: rimWidth * 0.8)
                        .overlay(Circle().stroke(accentMetal, lineWidth: 0.4 * unit))
                        .offset(x: s * rimWidth * 2.0)
                }
            }
        }
        .offset(y: -rr)
    }
}

// MARK: - 固有フレーム意匠（ベクター）

/// 三角形（先端を上に向けた二等辺）。コンパスの矢印などに使う。
private struct FrameTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 4方向に尖った煌めき（スパークル）。月白の星に使う。
private struct FourPointStar: Shape {
    var waist: CGFloat = 0.16
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let w = r * waist
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addLine(to: CGPoint(x: c.x + w, y: c.y - w))
        path.addLine(to: CGPoint(x: c.x + r, y: c.y))
        path.addLine(to: CGPoint(x: c.x + w, y: c.y + w))
        path.addLine(to: CGPoint(x: c.x, y: c.y + r))
        path.addLine(to: CGPoint(x: c.x - w, y: c.y + w))
        path.addLine(to: CGPoint(x: c.x - r, y: c.y))
        path.addLine(to: CGPoint(x: c.x - w, y: c.y - w))
        path.closeSubpath()
        return path
    }
}

/// 信号線（低位）— 上部のノードから下方へ広がる放送波＋細い受信目盛。
private struct SignalFrameShape: View {
    let primary: Color
    let luminous: Color
    let secondary: Color
    let width: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(primary.opacity(0.85), lineWidth: width)

            // 上部ノードから放射する3重の波。
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: 0.1, to: 0.4)
                    .stroke(
                        luminous.opacity(0.95 - Double(index) * 0.24),
                        style: StrokeStyle(lineWidth: max(1.5, width - 0.5), lineCap: .round)
                    )
                    .frame(
                        width: radius * (0.46 + CGFloat(index) * 0.32),
                        height: radius * (0.46 + CGFloat(index) * 0.32)
                    )
                    .offset(y: -radius * 0.6)
            }
            // 発信ノード。
            Circle()
                .fill(luminous)
                .frame(width: width + 3, height: width + 3)
                .offset(y: -radius * 0.6)

            // 下半分の受信目盛。
            ForEach(0..<7, id: \.self) { index in
                Capsule()
                    .fill(primary.opacity(0.55))
                    .frame(width: 1.5, height: index == 3 ? 7 : 4)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(150 + Double(index) * 10))
            }
        }
    }
}

/// 方位（中位）— 計器のような細目盛＋四方位の矢、上に大きなNの矢。
private struct CompassFrameShape: View {
    let primary: Color
    let luminous: Color
    let secondary: Color
    let width: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(primary, lineWidth: width)
            Circle()
                .stroke(primary.opacity(0.3), lineWidth: 1)
                .scaleEffect(0.82)

            // 細かい度目盛。
            ForEach(0..<24, id: \.self) { index in
                Capsule()
                    .fill(primary.opacity(0.5))
                    .frame(width: 1, height: index % 6 == 0 ? 6 : 3)
                    .offset(y: -radius + 1)
                    .rotationEffect(.degrees(Double(index) / 24 * 360))
            }

            // 東西南の方位矢。
            ForEach(1..<4, id: \.self) { index in
                FrameTriangle()
                    .fill(luminous.opacity(0.9))
                    .frame(width: width + 2, height: width + 3)
                    .rotationEffect(.degrees(180))
                    .offset(y: -radius + width)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
            // 北の矢（大きく強調）。
            FrameTriangle()
                .fill(LinearGradient(colors: [luminous, primary], startPoint: .top, endPoint: .bottom))
                .frame(width: width + 5, height: width + 8)
                .offset(y: -radius + width * 0.5)
                .shadow(color: primary.opacity(0.6), radius: 2)
        }
    }
}

/// 月白（上位）— 二重環＋上部の三日月＋環上に散る星と細点。豪華。
private struct TsukishiroFrameShape: View {
    let primary: Color
    let luminous: Color
    let secondary: Color
    let width: CGFloat
    let radius: CGFloat

    private let starAngles: [Double] = [-52, 38, 96, 158, 214, 286]

    var body: some View {
        ZStack {
            // 二重環。
            Circle()
                .stroke(
                    AngularGradient(colors: [primary, luminous, primary, luminous, primary], center: .center, angle: .degrees(-90)),
                    lineWidth: width
                )
            Circle()
                .stroke(luminous.opacity(0.45), lineWidth: 1)
                .scaleEffect(0.86)
            Circle()
                .stroke(luminous.opacity(0.3), lineWidth: 1)
                .scaleEffect(1.05)

            // 環上に散る星。
            ForEach(Array(starAngles.enumerated()), id: \.offset) { pair in
                FourPointStar()
                    .fill(luminous)
                    .frame(
                        width: pair.offset.isMultiple(of: 2) ? width + 4 : width + 1,
                        height: pair.offset.isMultiple(of: 2) ? width + 4 : width + 1
                    )
                    .offset(y: -radius)
                    .rotationEffect(.degrees(pair.element))
            }
            // 星のあいだの細点。
            ForEach(0..<12, id: \.self) { index in
                Circle()
                    .fill(luminous.opacity(0.5))
                    .frame(width: 1.6, height: 1.6)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(index) / 12 * 360 + 15))
            }

            // 上部の三日月。
            crescent
                .frame(width: radius * 0.5, height: radius * 0.5)
                .offset(y: -radius * 0.6)
        }
    }

    private var crescent: some View {
        ZStack {
            Circle().fill(luminous)
            Circle()
                .fill(luminous)
                .scaleEffect(0.92)
                .offset(x: radius * 0.12)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .shadow(color: luminous.opacity(0.7), radius: 3)
    }
}

struct ProfileStatsRow: View {
    let streak: Int
    let totalScore: Int
    let friendCount: Int
    let streakIcon: ProfileStreakIconStyle

    var body: some View {
        HStack(spacing: 10) {
            ProfileStatTile(title: "ストリーク", value: "\(streak)日", systemImage: streakIcon.systemImage, tint: Color(hex: streakIcon.tintHex))
            ProfileStatTile(title: "継続XP", value: "\(totalScore)pt", systemImage: "sparkles", tint: LiminalTheme.reward)
            ProfileStatTile(title: "友達", value: "\(friendCount)人", systemImage: "person.2.fill", tint: Color(hex: "#27AE60"))
        }
    }
}

struct ProfileStatTile: View {
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        let _ = themeTransitionProgress
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(LiminalTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption)
                .foregroundStyle(LiminalTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LiminalTheme.surface)
        )
        .overlay(alignment: .topTrailing) {
            tint.opacity(0.18)
                .frame(width: 26, height: 4)
                .clipShape(Capsule())
                .padding(10)
        }
    }
}

struct ProfileNextUnlockSection: View {
    let targets: [ProfileUnlockTarget]
    let showsGalleryIndicator: Bool
    let onOpenGallery: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("次の解放")
                    .font(.headline)
                Spacer()
                Button {
                    onOpenGallery()
                } label: {
                    HStack(spacing: 4) {
                        if showsGalleryIndicator {
                            Circle()
                                .fill(LiminalTheme.reward)
                                .frame(width: 7, height: 7)
                                .accessibilityHidden(true)
                        }
                        Text("もっと見る")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiminalTheme.accent)
                }
                .buttonStyle(.plain)
            }

            if targets.isEmpty {
                ProfileAllUnlockedCard()
            } else {
                VStack(spacing: 10) {
                    ForEach(targets) { target in
                        ProfileUnlockTargetRow(target: target)
                    }
                }
            }
        }
    }
}

private struct ProfileUnlockTargetRow: View {
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    let target: ProfileUnlockTarget

    private var tint: Color {
        Color(hex: target.tintHex)
    }

    private var remainingLabel: String {
        target.remainingText
    }

    var body: some View {
        let _ = themeTransitionProgress
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                Image(systemName: target.systemImageName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(target.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(target.kindTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.12), in: Capsule())
                }

                Text(target.conditionText)
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                ProgressView(value: target.progress)
                    .tint(tint)

                HStack {
                    Text(remainingLabel)
                    Spacer(minLength: 8)
                    Text(target.progressText)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(LiminalTheme.secondaryText)
            }
        }
        .padding(12)
        .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileAllUnlockedCard: View {
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress

    var body: some View {
        let _ = themeTransitionProgress
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(hex: "#27AE60"))
                .frame(width: 42, height: 42)
                .background(Color(hex: "#27AE60").opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("全解放済み")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                Text("今の装備を磨ける状態")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ProfileCollectionSection: View {
    let badges: [ProfileBadgeModel]
    let equippedBadge: ProfileBadgeModel
    let iconFrame: ProfileIconFrameStyle
    let streakIcon: ProfileStreakIconStyle
    let cardStyle: ProfileCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("装備中")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ProfileEquipmentTile(title: "バッジ", value: equippedBadge.title, systemImage: equippedBadge.systemImage, tint: Color(hex: equippedBadge.tint))
                ProfileEquipmentFrameTile(title: "フレーム", value: iconFrame.title, frameStyle: iconFrame)
                ProfileEquipmentCardStyleTile(title: "カード", value: cardStyle.title, cardStyle: cardStyle, accentColor: iconFrame.primaryColor)
                ProfileEquipmentTile(title: "連続", value: streakIcon.title, systemImage: streakIcon.systemImage, tint: Color(hex: streakIcon.tintHex))
            }
        }
    }
}

private struct ProfileCollectionBadge: View {
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    let badge: ProfileBadgeModel
    let isEquipped: Bool

    private var tint: Color {
        Color(hex: badge.tint)
    }

    var body: some View {
        let _ = themeTransitionProgress
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(badge.isUnlocked ? tint.opacity(0.18) : LiminalTheme.surface)
                Circle()
                    .stroke(
                        isEquipped ? tint : (badge.isUnlocked ? tint.opacity(0.65) : LiminalTheme.divider.opacity(0.7)),
                        lineWidth: isEquipped ? 2 : 1
                    )
                Image(systemName: badge.isUnlocked ? badge.systemImage : "lock.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(badge.isUnlocked ? tint : LiminalTheme.secondaryText)
            }
            .frame(width: 62, height: 62)
            .overlay(alignment: .bottomTrailing) {
                if isEquipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .background(LiminalTheme.surface, in: Circle())
                }
            }

            Text(badge.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LiminalTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(badge.progressText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(LiminalTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 78)
        .opacity(badge.isUnlocked ? 1 : 0.55)
    }
}

struct ProfileEquipmentTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        ProfileEquipmentTileShell(title: title, value: value) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(height: 20)
        }
    }
}

struct ProfileEquipmentFrameTile: View {
    let title: String
    let value: String
    let frameStyle: ProfileIconFrameStyle

    var body: some View {
        ProfileEquipmentTileShell(title: title, value: value) {
            if frameStyle.id == ProfileDecorationUnlocks.noIconFrameID {
                Image(systemName: frameStyle.systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .frame(height: 20)
            } else {
                ZStack {
                    Circle()
                        .fill(frameStyle.primaryColor.opacity(0.14))
                        .frame(width: 22, height: 22)

                    ProfileIconFrameView(style: frameStyle, accentColor: frameStyle.primaryColor, size: 28)
                }
                .frame(width: 32, height: 24, alignment: .leading)
            }
        }
    }
}

struct ProfileEquipmentCardStyleTile: View {
    let title: String
    let value: String
    let cardStyle: ProfileCardStyle
    let accentColor: Color

    var body: some View {
        ProfileEquipmentTileShell(title: title, value: value) {
            ProfileMiniCardStyleView(style: cardStyle, accentColor: accentColor)
                .frame(width: 58, height: 34)
        }
    }
}

struct ProfileEquipmentTileShell<Preview: View>: View {
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    let title: String
    let value: String
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        let _ = themeTransitionProgress
        VStack(alignment: .leading, spacing: 8) {
            preview()
                .frame(height: 34, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiminalTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(LiminalTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .frame(minHeight: 78, alignment: .leading)
        .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ProfileMiniCardStyleView: View {
    let style: ProfileCardStyle
    let accentColor: Color

    var body: some View {
        ProfileDecoratedCardBackground(style: style, accentColor: accentColor, cornerRadius: 4)
    }
}

extension Color {
    /// 2色を線形補間する。グラデ/グロー生成で「同系色のなかで明度差だけ作る」ために使う。
    func liminalBlend(with other: Color, amount: CGFloat) -> Color {
        let from = UIColor(self)
        let to = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t)
        )
    }

    /// 発光ハイライト用に白へ寄せた明るい同系色。
    var liminalLuminous: Color { liminalBlend(with: .white, amount: 0.5) }
}
