// ID → 描画の振り分け。モチーフを足すときはここに1行ずつ足す。
import SwiftUI

protocol DecoMotif {
    /// フレーム：単位円（アバター半径=1）座標の描画命令
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp]
    /// カード：共通土台の上に角・縁の装飾を描く
    static func card(_ ctx: GraphicsContext, _ cc: CardContext)
}

enum DecoCatalog {
    static func motif(_ id: DecorationID) -> DecoMotif.Type? {
        switch id {
        case .rippleBorder: return RippleMotif.self
        case .frostEdge: return FrostMotif.self
        case .candle: return CandleMotif.self
        case .ink: return InkMotif.self
        case .threadBorder: return ThreadMotif.self
        case .cloudVeil: return CloudMotif.self
        case .mist: return MistMotif.self
        case .auroraTrace: return AuroraMotif.self
        case .dawnHorizon: return DawnMotif.self
        case .sunline: return SunlineMotif.self
        case .orbitGrid: return OrbitMotif.self
        case .rain: return RainMotif.self
        case .glassBead: return GlassMotif.self
        case .linenStitch: return LinenMotif.self
        case .wave: return WaveMotif.self
        case .petalCorner: return PetalMotif.self
        case .stonePath: return StoneMotif.self
        case .nightBloom: return NightBloomMotif.self
        case .leafCorner: return LeafMotif.self
        case .constellation: return StarChartMotif.self
        default: return nil
        }
    }

    static var implemented: [DecorationID] { DecorationID.allCases.filter { motif($0) != nil } }

    static func frameOps(_ id: DecorationID, detail: Detail, scheme: DecoScheme) -> [DrawOp] {
        guard let m = motif(id) else { return PlaceholderMotif.frame(detail, scheme, id.palette) }
        return m.frame(detail, scheme, id.palette)
    }

    static func drawCard(_ id: DecorationID, _ ctx: GraphicsContext, _ cc: CardContext) {
        guard let m = motif(id) else { PlaceholderMotif.card(ctx, cc); return }
        m.card(ctx, cc)
    }
}

/// 未実装IDの仮表示（一覧で抜けが分かるように、地と罫だけ）
enum PlaceholderMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        [DrawOp(z: 0) { c in
            c.stroke(disc(.zero, 1.0), with: .color(pal.line(s).c(0.5)), style: StrokeStyle(lineWidth: d.w(0.01, minPx: 1), dash: [0.03, 0.03]))
        }]
    }
    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        CardBase.drawGround(ctx, cc, seed: 1)
        CardBase.drawRule(ctx, cc, finial: nil)
    }
}
