// Experimental artwork only. Not linked to the Liminalog app target.
// All candidate artwork is drawn by SwiftUI Canvas; no raster assets are sampled.
import SwiftUI

func ink(_ hex: UInt32, _ opacity: Double = 1) -> Color {
    Color(.sRGB, red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, opacity: opacity)
}

enum StudyMotif: String, CaseIterable {
    case botanical, celestial
    var title: String { self == .botanical ? "葉隅" : "星図線" }
    var sourceID: String { self == .botanical ? "free_leaf_corner" : "free_constellation" }
    var accent: Color { self == .botanical ? ink(0x87D8BB) : ink(0xAACCF4) }
}

private func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x:x, y:y) }
private func polar(_ a: Double, _ r: Double, _ cx: Double = 300, _ cy: Double = 300) -> CGPoint {
    point(cx + cos(a * .pi / 180) * r, cy + sin(a * .pi / 180) * r)
}
private func disc(_ p: CGPoint, _ r: Double) -> Path {
    Path(ellipseIn: CGRect(x:p.x-r, y:p.y-r, width:r*2, height:r*2))
}
private func line(_ points: [CGPoint]) -> Path {
    Path { p in guard let first = points.first else { return }; p.move(to:first); for next in points.dropFirst() {p.addLine(to:next)} }
}
private func stroke(_ c: GraphicsContext, _ p: Path, _ color: Color, _ width: Double) {
    c.stroke(p, with:.color(color), style:StrokeStyle(lineWidth:width, lineCap:.round, lineJoin:.round))
}
private func arc(_ radius: Double, _ from: Double, _ to: Double, cx: Double = 300, cy: Double = 300) -> Path {
    Path { p in p.addArc(center:point(cx,cy), radius:radius, startAngle:.degrees(from), endAngle:.degrees(to), clockwise:false) }
}
private func sparkle(_ c: GraphicsContext, at p: CGPoint, radius: Double, color: Color, halo: Bool = true) {
    var local = c
    local.translateBy(x:p.x, y:p.y)
    let path = Path { p in
        p.move(to:point(0,-radius))
        p.addQuadCurve(to:point(radius,0), control:point(radius*0.12,-radius*0.12))
        p.addQuadCurve(to:point(0,radius), control:point(radius*0.12,radius*0.12))
        p.addQuadCurve(to:point(-radius,0), control:point(-radius*0.12,radius*0.12))
        p.addQuadCurve(to:point(0,-radius), control:point(-radius*0.12,-radius*0.12))
    }
    if halo {
        local.fill(disc(.zero,radius*1.8),with:.radialGradient(Gradient(colors:[color.opacity(0.26),color.opacity(0)]),center:.zero,startRadius:0,endRadius:radius*1.8))
    }
    stroke(local,path,ink(0x253747,0.72),1.0)
    local.fill(path, with:.color(color))
    local.fill(disc(.zero,radius*0.13),with:.color(ink(0xFFFFFF)))
}

private struct BotanicalPen {
    static func leaf(_ context: GraphicsContext, at p: CGPoint, angle: Double, length: Double, width: Double, pale: Bool = false, detail: Bool = true) {
        var c = context
        c.translateBy(x:p.x,y:p.y)
        c.rotate(by:.degrees(angle))
        let leaf = Path { p in
            p.move(to:.zero)
            p.addCurve(to:point(length,0),control1:point(length*0.23,-width*0.7),control2:point(length*0.78,-width*0.50))
            p.addCurve(to:.zero,control1:point(length*0.8,width*0.55),control2:point(length*0.16,width*0.46))
        }
        let colors = pale ? [ink(0x7DAB9A),ink(0xD2DBB3),ink(0x608F83)] : [ink(0x265B54),ink(0x70BCA4),ink(0x325F5C)]
        c.fill(leaf, with:.linearGradient(Gradient(colors:colors),startPoint:point(0,-width*0.5),endPoint:point(length,width*0.55)))
        stroke(c,leaf,ink(0xC8E6C3,0.65),max(0.65,length*0.015))
        var vein = Path()
        vein.move(to:point(0,0)); vein.addQuadCurve(to:point(length*0.94,0),control:point(length*0.55,-width*0.08))
        stroke(c,vein,ink(0xDCE9C6,0.72),max(0.6,length*0.014))
        if detail {
            for i in 1...4 {
                let t = Double(i)/6
                let x = length*t
                let v = width*sin(t * .pi)*0.35
                for side in [-1.0,1.0] {
                    let vp = Path { p in
                        p.move(to:point(x, -width*0.025))
                        p.addQuadCurve(to:point(x+length*0.14,side*v),control:point(x+length*0.11,side*v*0.4))
                    }
                    stroke(c,vp,ink(0xE0ECCA,0.34),0.48)
                }
            }
        }
        let highlight = Path { p in
            p.move(to:point(length*0.18,-width*0.18))
            p.addQuadCurve(to:point(length*0.8,-width*0.08),control:point(length*0.5,-width*0.36))
        }
        stroke(c,highlight,ink(0xE8F3D7,0.28),0.8)
    }

    static func flower(_ context: GraphicsContext, at center: CGPoint, radius: Double, rotation: Double) {
        var c = context
        c.translateBy(x:center.x,y:center.y)
        c.rotate(by:.degrees(rotation))
        for i in 0..<5 {
            var petalContext = c
            petalContext.rotate(by:.degrees(Double(i)*72))
            let p = Path { p in
                p.move(to:point(0,0))
                p.addCurve(to:point(0,-radius),control1:point(-radius*0.85,-radius*0.3),control2:point(-radius*0.57,-radius*1.18))
                p.addCurve(to:point(0,0),control1:point(radius*0.57,-radius*1.1),control2:point(radius*0.63,-radius*0.28))
            }
            petalContext.fill(p,with:.linearGradient(Gradient(colors:[ink(0xAFB9A0),ink(0xF1EACA),ink(0xDEE7CC)]),startPoint:.zero,endPoint:point(0,-radius)))
            stroke(petalContext,p,ink(0xF4E6BD,0.85),0.55)
            stroke(petalContext,line([point(0,-radius*0.22),point(0,-radius*0.8)]),ink(0x9B9A73,0.32),0.5)
        }
        c.fill(disc(.zero,radius*0.22),with:.color(ink(0xC5A264)))
        for i in 0..<6 { c.fill(disc(polar(Double(i)*60,radius*0.13,0,0),radius*0.045),with:.color(ink(0xFFF1CD))) }
    }

    static func bud(_ context: GraphicsContext, at p: CGPoint, radius: Double) {
        context.fill(disc(p,radius),with:.radialGradient(Gradient(colors:[ink(0xECDBAD),ink(0xB49564),ink(0x576B58)]),center:point(p.x-radius*0.28,p.y-radius*0.3),startRadius:0,endRadius:radius*1.65))
        stroke(context,disc(p,radius),ink(0xE8D7A8,0.65),0.65)
        context.fill(disc(point(p.x-radius*0.22,p.y-radius*0.28),radius*0.2),with:.color(ink(0xFFF9DF,0.85)))
    }

    static func sprig(_ context: GraphicsContext, at p: CGPoint, angle: Double, scale: Double, detail: Bool) {
        var c = context
        c.translateBy(x:p.x,y:p.y); c.rotate(by:.degrees(angle)); c.scaleBy(x:scale,y:scale)
        let stem = Path { p in p.move(to:.zero); p.addCurve(to:point(108,-5),control1:point(36,-20),control2:point(80,11)) }
        stroke(c,stem,ink(0xBFD9AC,0.75),1.3)
        leaf(c,at:point(15,-5),angle:-52,length:40,width:20,detail:detail)
        leaf(c,at:point(31,-7),angle:49,length:40,width:21,pale:true,detail:detail)
        leaf(c,at:point(51,-5),angle:-43,length:37,width:18,detail:detail)
        leaf(c,at:point(72,-3),angle:43,length:29,width:14,pale:true,detail:detail)
        leaf(c,at:point(86,-2),angle:-18,length:34,width:13,detail:detail)
        for i in 0..<3 {
            let x = 24 + Double(i)*22
            let y = -28 - Double(i%2)*8
            stroke(c,line([point(x,-7),point(x+3,y)]),ink(0x9FBEA3,0.65),0.85)
            bud(c,at:point(x+3,y),radius:2.8)
        }
    }
}

struct NativeDecorationFrame: View {
    let motif: StudyMotif
    var body: some View {
        Canvas { context, size in
            var c = context
            c.scaleBy(x:size.width/600,y:size.height/600)
            // The ring centerline is fixed at 38.2% of the artwork width.
            // At 82pt avatar size, the existing 1.12 * (size+16) display gives r=41.9pt.
            let detail = size.width >= 72
            if motif == .botanical { botanical(c,detail:detail) } else { celestial(c,detail:detail) }
        }.accessibilityHidden(true)
    }

    private func botanical(_ c: GraphicsContext, detail: Bool) {
        stroke(c,arc(229,-180,180),ink(0x213E3A,0.9),5.5)
        for (radius,width,alpha) in [(229.0,2.4,0.9),(233.0,0.9,0.6),(225.0,0.8,0.5)] {
            c.stroke(arc(radius,-180,180),with:.linearGradient(Gradient(colors:[ink(0xE3DCB4,alpha),ink(0x6EA997,alpha),ink(0xE5D3A3,alpha)]),startPoint:point(100,50),endPoint:point(480,560)),lineWidth:width)
        }
        // Braided stems move subtly across the ring instead of reading as three perfect wires.
        for j in 0..<2 {
            let points = (0...240).map { i -> CGPoint in
                let a = Double(i)*1.5
                return polar(a,229 + sin(a * .pi / 180 * 5 + Double(j)*2.6)*4.6)
            }
            stroke(c,line(points),ink(j == 0 ? 0xCEC69F : 0x91B99E,0.65),1.2)
        }
        let clusters: [(Double,Double,Double)] = [(-170,0.9,1),(-145,1.3,-1),(-113,0.95,1),(-85,1.2,-1),(-54,0.85,1),(-23,1.18,-1),(7,0.95,1),(33,1.25,-1),(65,0.85,1),(91,1.25,-1),(122,1.0,1),(151,1.2,-1),(174,0.7,1)]
        for (i,entry) in clusters.enumerated() {
            let (a,s,side) = entry
            let p = polar(a,230)
            var branch = c; branch.translateBy(x:p.x,y:p.y); branch.rotate(by:.degrees(a+90))
            let stem = Path { p in p.move(to:point(-21,0)); p.addQuadCurve(to:point(50,-side*8),control:point(20,-side*10)) }
            stroke(branch,stem,ink(0xC4D8AC,0.9),1.1)
            BotanicalPen.leaf(branch,at:point(-10,0),angle:-side*49,length:34*s,width:17*s,pale:i%3 == 0,detail:detail)
            BotanicalPen.leaf(branch,at:point(12,-side*3),angle:side*42,length:30*s,width:15*s,pale:i%3 == 1,detail:detail)
            BotanicalPen.leaf(branch,at:point(30,-side*6),angle:-side*30,length:25*s,width:12*s,detail:detail)
            stroke(branch,line([point(4,-1),point(15,-side*24)]),ink(0xD6C499,0.8),0.9)
            BotanicalPen.bud(branch,at:point(15,-side*24),radius:3.5*s)
        }
        for a in [-159.0,-100,-40,20,79,138] {
            let root = polar(a,230)
            var fern = c; fern.translateBy(x:root.x,y:root.y); fern.rotate(by:.degrees(a+83))
            stroke(fern,line([point(0,0),point(45,-8)]),ink(0xBACBA3,0.9),1.1)
            for i in 1...5 {
                let x = Double(i)*7
                for side in [-1.0,1.0] {
                    BotanicalPen.leaf(fern,at:point(x,-x*0.17),angle:side*55,length:17-Double(i),width:6.5,pale:i%2 == 0,detail:false)
                }
            }
        }
        for (a,r,s) in [(-137.0,237.0,13.0),(-53,230,10),(29,230,14),(112,237,12),(177,230,10)] {
            BotanicalPen.flower(c,at:polar(a,r),radius:s,rotation:a)
        }
        for i in 0..<22 {
            let a = Double(i)*137.508
            let r = 250 + sin(Double(i)*2.7)*8
            c.fill(disc(polar(a,r),i%4 == 0 ? 1.4 : 0.75),with:.color(ink(0xD7DFB3,0.6)))
        }
    }

    private func celestial(_ c: GraphicsContext, detail: Bool) {
        // A translucent woven body gives the constellation a material silhouette.
        var ribbon = Path()
        let outer = (0...180).map { i in polar(Double(i)*2,234 + sin(Double(i)*0.19)*4) }
        let inner = (0...180).reversed().map { i in polar(Double(i)*2,222 + sin(Double(i)*0.19+0.5)*4) }
        ribbon.addLines(outer + inner); ribbon.closeSubpath()
        c.fill(ribbon,with:.linearGradient(Gradient(colors:[ink(0x2C425A,0.85),ink(0x6C879C,0.6),ink(0x313850,0.85)]),startPoint:point(120,30),endPoint:point(500,550)))
        for j in 0..<4 {
            let pts = (0...180).map { i in polar(Double(i)*2,223+Double(j)*4 + sin(Double(i)*0.14+Double(j))*4) }
            stroke(c,line(pts),ink(j%2 == 0 ? 0x9EBBD3 : 0xC6BC94,0.3),0.7)
        }
        stroke(c,arc(229,-180,180),ink(0x253949,0.8),4.7)
        for i in 0..<3 {
            let ring = arc(224+Double(i)*5,-180,180)
            stroke(c,ring,ink(i == 1 ? 0xB8B493 : 0x739DC3,i == 1 ? 0.72 : 0.38),i == 1 ? 1.7 : 0.65)
        }
        for i in 0..<6 {
            let start = Double(i)*60-85
            stroke(c,arc(241,start,start+28),ink(0xB6D6E7,0.6),0.85)
            stroke(c,arc(218,start+4,start+40),ink(0xCCBA86,0.55),0.7)
        }
        for i in 0..<72 {
            let a = Double(i)*5
            let p = polar(a,246)
            let q = polar(a,i%3 == 0 ? 251 : 248)
            stroke(c,line([p,q]),ink(0xCFDDBD,i%3 == 0 ? 0.6 : 0.25),0.75)
        }
        let angles = [-170.0,-151,-137,-119,-96,-82,-62,-47,-27,-11,7,24,46,63,82,103,119,137,154,174]
        let radii = [235.0,216,239,231,248,223,231,216,241,231,217,242,228,217,237,220,242,232,216,241]
        let nodes = zip(angles,radii).map { polar($0.0,$0.1) }
        for i in nodes.indices {
            if i%5 != 4 {
                stroke(c,line([nodes[i],nodes[(i+1)%nodes.count]]),ink(0xD8CFAB,0.76),1.0)
            }
            if i%5 == 1 {
                stroke(c,line([nodes[i],polar(angles[i]+10,252),nodes[min(i+2,nodes.count-1)]]),ink(0x91BAD6,0.46),0.75)
            }
            if i%3 == 0 {
                sparkle(c,at:nodes[i],radius:i%2 == 0 ? 10 : 7,color:ink(0xF1E4B5))
            } else {
                c.fill(disc(nodes[i],3.0),with:.color(ink(0xC5E6F5)))
                if i%4 == 0 { stroke(c,disc(nodes[i],4.6),ink(0xD1CA9F,0.8),0.8) }
            }
        }
        for (a,r) in [(-87.0,238.0),(94,235)] {
            let p = polar(a,r)
            stroke(c,disc(p,8.5),ink(0xC8BC8D,0.7),0.8)
            stroke(c,disc(p,11.5),ink(0xAAC5D9,0.45),0.65)
            sparkle(c,at:p,radius:5.5,color:ink(0xF4E6AF))
        }
        if detail {
            for i in 0..<85 {
                let a = Double(i)*137.508
                let radius = 218 + (sin(Double(i)*8.31)+1)*20
                c.fill(disc(polar(a,radius),i%7 == 0 ? 1.15 : 0.58),with:.color(ink(0xB8D5ED,0.25 + Double(i%4)*0.12)))
            }
        }
    }
}

struct NativeDecorationCard: View {
    let motif: StudyMotif
    var body: some View {
        Canvas { context, size in
            var c = context
            c.scaleBy(x:size.width/1000,y:size.height/650)
            let bounds = CGRect(x:0,y:0,width:1000,height:650)
            let shape = Path(roundedRect:bounds,cornerRadius:52)
            c.clip(to:shape)
            let colors = motif == .botanical ? [ink(0x132826),ink(0x1A3032),ink(0x14202E)] : [ink(0x171D37),ink(0x252D4B),ink(0x151D32)]
            c.fill(shape,with:.linearGradient(Gradient(colors:colors),startPoint:.zero,endPoint:point(1000,650)))
            let light = motif == .botanical ? ink(0x6DB994,0.13) : ink(0x9DB2EE,0.13)
            c.fill(shape,with:.radialGradient(Gradient(colors:[light,.clear]),center:point(100,50),startRadius:0,endRadius:650))
            // Stable, low contrast pigment grain; seed does not change across renders.
            for i in 0..<800 {
                let x = Double((i*137+37)%997)
                let y = Double((i*311+91)%647)
                c.fill(disc(point(x,y),i%7 == 0 ? 0.85 : 0.45),with:.color(ink(0xDCE8F0,0.022 + Double(i%3)*0.008)))
            }
            let border = motif == .botanical ? ink(0xADCEA7,0.5) : ink(0xC5C6E1,0.48)
            stroke(c,Path(roundedRect:bounds.insetBy(dx:10,dy:10),cornerRadius:44),border,1.6)
            stroke(c,Path(roundedRect:bounds.insetBy(dx:17,dy:17),cornerRadius:38),border.opacity(0.5),0.65)
            if motif == .botanical { botanical(c) } else { celestial(c) }
        }.accessibilityHidden(true)
    }
    private func botanical(_ c: GraphicsContext) {
        // Two composed corner sprays, not repeated symbols around every edge.
        for (p,a,s,o) in [(point(-4,174),-63.0,1.62,1.0),(point(20,180),-21,1.43,0.68),(point(55,27),20,1.05,0.5)] {
            var branch = c; branch.opacity = o
            BotanicalPen.sprig(branch,at:p,angle:a,scale:s,detail:true)
        }
        var lower = c; lower.translateBy(x:1000,y:650); lower.rotate(by:.degrees(180)); lower.scaleBy(x:0.65,y:0.65)
        for (p,a,s,o) in [(point(1,132),-62.0,1.55,1.0),(point(24,174),-18,1.45,0.68),(point(50,25),17,1.08,0.5)] {
            var branch = lower; branch.opacity = o
            BotanicalPen.sprig(branch,at:p,angle:a,scale:s,detail:true)
        }
        BotanicalPen.flower(c,at:point(72,66),radius:15,rotation:12)
        BotanicalPen.flower(lower,at:point(65,64),radius:15,rotation:38)
        for (x,y) in [(204.0,32.0),(172,60),(146,22),(812,605),(841,626),(909,563)] {
            sparkle(c,at:point(x,y),radius:2.6,color:ink(0xDBDBAB,0.7),halo:false)
        }
        for y in [17.0,633.0] {
            let p = point(500,y)
            BotanicalPen.leaf(c,at:p,angle:180,length:11,width:5,pale:true,detail:false)
            BotanicalPen.leaf(c,at:p,angle:0,length:11,width:5,pale:true,detail:false)
            c.fill(disc(p,2),with:.color(ink(0xDCCB9C)))
        }
    }
    private func celestial(_ c: GraphicsContext) {
        // Celestial cartography stays in the rim and leaves a quiet text field.
        for (cx,cy,start,end) in [(-18.0,-18.0,3.0,87.0),(1018,668,183,267)] {
            for r in [125.0,170,220,276] {
                c.stroke(arc(r,start,end,cx:cx,cy:cy),with:.color(ink(0xAABEDC,0.27)),style:StrokeStyle(lineWidth:0.8,dash:[1.2,5]))
            }
        }
        let constellations: [[CGPoint]] = [
            [point(27,103),point(77,68),point(117,85),point(162,40),point(208,59),point(250,29)],
            [point(33,531),point(69,565),point(127,550),point(163,609),point(203,619)],
            [point(799,34),point(855,56),point(915,37),point(961,78),point(938,122),point(978,160)],
            [point(784,612),point(844,587),point(881,615),point(912,571),point(967,583),point(958,526)]
        ]
        for (j,nodes) in constellations.enumerated() {
            stroke(c,line(nodes),ink(0xABC7E7,0.6),1.05)
            for (i,p) in nodes.enumerated() {
                if i%3 == 0 { sparkle(c,at:p,radius:5.2,color:ink(0xEEDBB1),halo:false) }
                else { c.fill(disc(p,2.4),with:.color(ink(j%2 == 0 ? 0xBADEF0 : 0xC9C6EF))) }
            }
        }
        for i in 0..<47 {
            let x = Double((i*167+37)%940)+30
            let y = i%2 == 0 ? Double((i*43)%52)+25 : 565+Double((i*37)%50)
            if i%6 == 0 { sparkle(c,at:point(x,y),radius:3.8,color:ink(0xCDD9F1,0.7),halo:false) }
            else { c.fill(disc(point(x,y),0.9),with:.color(ink(0xC3D5EC,0.6))) }
        }
        for y in [17.0,633.0] { sparkle(c,at:point(500,y),radius:6.5,color:ink(0xE8DFBD),halo:false) }
    }
}
