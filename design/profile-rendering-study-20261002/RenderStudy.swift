import SwiftUI
import AppKit

let studyDirectory = URL(fileURLWithPath:CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let repository = studyDirectory.deletingLastPathComponent().deletingLastPathComponent()
let output = studyDirectory.appendingPathComponent("renders")
func jp(_ size: CGFloat, bold: Bool = false) -> Font { .custom(bold ? "HiraginoSans-W6" : "HiraginoSans-W3",size:size) }

struct SourceArt: View {
    let motif: StudyMotif
    let card: Bool
    var body: some View {
        let name = card ? "Cards/profile_card_\(motif.sourceID)_panel.png" : "Frames/profile_frame_\(motif.sourceID).png"
        let url = repository.appendingPathComponent("decoration-masters/\(name)")
        if let image = NSImage(contentsOf:url) {
            Image(nsImage:image).resizable().interpolation(.high)
        } else { Color.red.overlay(Text("Missing reference")) }
    }
}

struct StudyAvatar: View {
    var motif: StudyMotif
    var native: Bool
    var size: CGFloat = 82
    var busy: Bool = false
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:busy ? [ink(0xDCE0D5),ink(0x7C9BB1),ink(0x162C45)] : [ink(0x72899A),ink(0x354758)],startPoint:.topLeading,endPoint:.bottomTrailing))
                .frame(width:size,height:size)
                .overlay {
                    if busy {
                        Circle().fill(ink(0xDEC8AA)).frame(width:size*0.34,height:size*0.34).offset(y:-size*0.12)
                        Ellipse().fill(ink(0x182A3C)).frame(width:size*0.76,height:size*0.58).offset(y:size*0.40)
                    } else {
                        Text("R").font(.system(size:size*0.37,weight:.medium,design:.serif)).foregroundStyle(ink(0xEBEFF2))
                    }
                }.clipShape(Circle())
            Circle().stroke(.white.opacity(0.7),lineWidth:1.4).frame(width:size,height:size)
            if native {
                NativeDecorationFrame(motif:motif).frame(width:size / 0.764,height:size / 0.764)
            } else {
                SourceArt(motif:motif,card:false).scaledToFit().frame(width:size / 0.764,height:size / 0.764)
            }
        }.frame(width:size+22,height:size+22)
    }
}

struct StudyHero: View {
    let motif: StudyMotif
    let native: Bool
    var width: CGFloat = 350
    var textScale: CGFloat = 1
    var busy: Bool = false
    var height: CGFloat { textScale > 1.2 ? 320 : 226 }
    var body: some View {
        ZStack(alignment:.topLeading) {
            if native {
                NativeDecorationCard(motif:motif).frame(width:width,height:height)
            } else {
                // Same transform as ProfileCardBackground: scaledToFill, 1.08, y=-24.
                SourceArt(motif:motif,card:true).aspectRatio(1.6,contentMode:.fill)
                    .frame(width:width,height:height).scaleEffect(1.08).offset(y:-24)
            }
            HStack(alignment:.top,spacing:12) {
                VStack(spacing:12) {
                    StudyAvatar(motif:motif,native:native,busy:busy)
                    HStack(spacing:14) {
                        Image(systemName:"pencil")
                        Image(systemName:"square.and.arrow.up")
                    }.font(.system(size:14,weight:.medium))
                }.frame(width:104)
                VStack(alignment:.leading,spacing:9) {
                    HStack {
                        Text("@ryu").font(.system(size:11*textScale))
                        Spacer(minLength:3)
                        Text("Lv. 24").font(.system(size:10*textScale,weight:.medium,design:.rounded))
                    }.foregroundStyle(native ? ink(0xBDCFD3) : ink(0xD8CEE8))
                    Text(textScale > 1.2 ? "りゅうの記録" : "Ryu")
                        .font(jp(23*textScale,bold:true)).fixedSize(horizontal:false,vertical:true)
                    HStack(spacing:4) {
                        Image(systemName:"leaf")
                        Text("日々を重ねる")
                    }.font(jp(10*textScale)).foregroundStyle(native ? motif.accent : ink(0xF7F2FF))
                    Text("予定と、その先にあったこと。\n小さな日々を残しています。")
                        .font(jp(11*textScale)).lineSpacing(5).fixedSize(horizontal:false,vertical:true)
                        .foregroundStyle(native ? ink(0xD3DFE1) : ink(0xD8CEE8))
                }.padding(.top,8)
            }
            .foregroundStyle(native ? ink(0xF0F3EC) : ink(0xF7F2FF))
            .shadow(color:native ? .clear : .black.opacity(0.55),radius:native ? 0 : 3,y:1)
            .padding(.horizontal,24).padding(.top,26)
        }.frame(width:width,height:height)
    }
}

struct StudyBoard: View {
    var body: some View {
        VStack(alignment:.leading,spacing:26) {
            VStack(alignment:.leading,spacing:10) {
                Text("LIMINALOG  /  MATERIAL STUDY 01").font(.system(size:11,weight:.medium,design:.monospaced)).tracking(2).foregroundStyle(ink(0xA1A6BA))
                Text("記録を包む、ふたつの装飾。").font(jp(28,bold:true))
                Text("コード描画の品質検証　・　採用未定").font(jp(12)).foregroundStyle(ink(0xB7BACC))
            }
            HStack {
                Text("既存の画像素材").frame(width:350,alignment:.leading)
                Spacer().frame(width:40)
                Text("SwiftUI Canvas 試作").frame(width:350,alignment:.leading)
            }.font(jp(12,bold:true)).foregroundStyle(ink(0xC6C8D5))
            ForEach(StudyMotif.allCases,id:\.self) { motif in
                VStack(alignment:.leading,spacing:17) {
                    HStack(spacing:10) {
                        Text(motif == .botanical ? "01" : "02").font(.system(size:11,design:.monospaced)).foregroundStyle(ink(0x8D94A7))
                        Text(motif.title).font(jp(16,bold:true))
                        Text(motif == .botanical ? "葉・蔓・小花の重なり" : "軌道・星・余白の重なり").font(jp(11)).foregroundStyle(ink(0x9EA7B7))
                    }
                    HStack(spacing:40) {
                        StudyHero(motif:motif,native:false)
                        StudyHero(motif:motif,native:true)
                    }.padding(.top,32)
                    HStack(spacing:40) {
                        sizeStrip(motif:motif,native:false)
                        sizeStrip(motif:motif,native:true)
                    }
                }
                Rectangle().fill(ink(0xFFFFFF,0.09)).frame(height:1)
            }
            VStack(alignment:.leading,spacing:7) {
                Text("今回の比較は同モチーフの再設計です。画像の忠実な複製を保証するものではありません。").font(jp(10))
                Text("右列の装飾本体はコード描画。左列は現行描画を参考にした合成です。カード領域・アバター・文字内容は共通です。").font(jp(10))
                Text("macOS 上の SwiftUI オフスクリーン描画。iOS 実機の見え方・性能・採用判断は未検証。").font(jp(10))
            }.foregroundStyle(ink(0x959FB2))
        }
        .padding(36).foregroundStyle(ink(0xECEEF5)).frame(width:812)
        .background(LinearGradient(colors:[ink(0x111623),ink(0x171B2C)],startPoint:.topLeading,endPoint:.bottomTrailing))
    }
    func sizeStrip(motif:StudyMotif,native:Bool) -> some View {
        HStack(alignment:.center,spacing:18) {
            ForEach([32.0,48.0,82.0],id:\.self) { size in
                VStack(spacing:7) {
                    StudyAvatar(motif:motif,native:native,size:size,busy:true)
                    Text("\(Int(size)) pt").font(.system(size:9,design:.monospaced)).foregroundStyle(ink(0x9DA7B9))
                }
            }
            Spacer(minLength:0)
        }.frame(width:350)
    }
}

struct StressBoard: View {
    let light: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:22) {
            Text(light ? "明るい画面での確認" : "暗い画面での確認").font(jp(24,bold:true))
            Text("コード試作のみ  /  小サイズ・長い名前・文字拡大相当").font(jp(12)).opacity(0.65)
            HStack(alignment:.top,spacing:24) {
                ForEach(StudyMotif.allCases,id:\.self) { m in
                    VStack(alignment:.leading,spacing:20) {
                        Text(m.title).font(jp(14,bold:true))
                        StudyHero(motif:m,native:true,width:350,textScale:1.55,busy:true)
                        HStack(spacing:13) {
                            ForEach([24.0,32,48,82],id:\.self) { sz in
                                StudyAvatar(motif:m,native:true,size:sz,busy:true)
                            }
                        }
                        NativeDecorationCard(motif:m).frame(width:120,height:75)
                        Text("カード一覧相当 120 × 75 pt").font(jp(10)).opacity(0.65)
                    }
                }
            }
        }.padding(32).frame(width:788)
            .foregroundStyle(light ? ink(0x242C3E) : ink(0xE5EAF3))
            .background(light ? ink(0xF2F1F7) : ink(0x111724))
    }
}

@main struct RenderStudy {
    @MainActor static func render<V: View>(_ view: V, name:String, scale:CGFloat = 2) throws {
        let r = ImageRenderer(content:view.environment(\.colorScheme,.dark))
        r.scale = scale
        guard let cg = r.cgImage else { fatalError("Render failed: \(name)") }
        let data = NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!
        try data.write(to:output.appendingPathComponent(name + ".png"))
        print("\(name): \(cg.width) × \(cg.height)")
    }
    @MainActor static func main() throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        try render(StudyBoard(),name:"comparison",scale:2)
        try render(StressBoard(light:false),name:"stress-dark",scale:2)
        try render(StressBoard(light:true),name:"stress-light",scale:2)
        for motif in StudyMotif.allCases {
            try render(NativeDecorationFrame(motif:motif).frame(width:1024,height:1024),name:"\(motif.rawValue)-frame-2048",scale:2)
            try render(NativeDecorationFrame(motif:motif).frame(width:512,height:512),name:"\(motif.rawValue)-frame-1024",scale:2)
            try render(NativeDecorationCard(motif:motif).frame(width:1024,height:682.5),name:"\(motif.rawValue)-card",scale:2)
            try render(StudyHero(motif:motif,native:true),name:"\(motif.rawValue)-hero",scale:3)
        }
    }
}
