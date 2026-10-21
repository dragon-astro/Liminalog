// Simulator-only quality study. Separate bundle identifier; no production data access.
import SwiftUI

private struct PreviewAvatar: View {
    let motif: StudyMotif
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[ink(0x8DADB9),ink(0x35495F)],startPoint:.topLeading,endPoint:.bottomTrailing))
                .frame(width:size,height:size)
            Text("R").font(.system(size:size*0.37,weight:.medium,design:.serif)).foregroundStyle(ink(0xEDF1EF))
            NativeDecorationFrame(motif:motif).frame(width:size/0.764,height:size/0.764)
        }.frame(width:size+16,height:size+16)
    }
}

private struct PreviewCard: View {
    let motif: StudyMotif
    let large: Bool
    var body: some View {
        HStack(alignment:.top,spacing:14) {
            VStack(spacing:15) {
                PreviewAvatar(motif:motif,size:82)
                HStack(spacing:20) {
                    Image(systemName:"pencil")
                    Image(systemName:"square.and.arrow.up")
                }.font(.system(size:15))
            }.frame(width:104)
            VStack(alignment:.leading,spacing:9) {
                HStack {
                    Text("@ryu").font(.caption)
                    Spacer(minLength:0)
                    Text("Lv. 24").font(.caption2)
                }.foregroundStyle(ink(0xBDCFD3))
                Text(large ? "りゅうの記録" : "Ryu").font(.title2.bold())
                    .fixedSize(horizontal:false,vertical:true)
                HStack(spacing:4) {
                    Image(systemName:"leaf")
                    Text("日々を重ねる")
                }.font(.caption).foregroundStyle(motif.accent)
                Text("予定と、その先にあったこと。\n小さな日々を残しています。")
                    .font(.footnote).lineSpacing(4).foregroundStyle(ink(0xD3DFE1))
                    .fixedSize(horizontal:false,vertical:true)
            }.padding(.top,6)
        }
        .foregroundStyle(ink(0xF0F3EC))
        .padding(24).frame(maxWidth:.infinity,alignment:.topLeading)
        .frame(minHeight:226,alignment:.top)
        .background { NativeDecorationCard(motif:motif) }
    }
}

@main struct ProfileDecorationStudyApp: App {
    var body: some Scene {
        WindowGroup {
            StudyScreen()
        }
    }
}

private struct StudyScreen: View {
    @State private var light = ProcessInfo.processInfo.arguments.contains("--light")
    @State private var large = ProcessInfo.processInfo.arguments.contains("--large")
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    VStack(alignment:.leading,spacing:6) {
                        Text("プロフィール装飾の試作").font(.title3.bold())
                        Text("コード描画の品質検証 · 採用未定")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(ProcessInfo.processInfo.arguments.contains("--celestial-first") ? [.celestial, .botanical] : StudyMotif.allCases,id:\.self) { motif in
                        VStack(alignment:.leading,spacing:12) {
                            Text(motif.title).font(.subheadline.bold())
                            PreviewCard(motif:motif,large:large)
                            HStack(spacing:12) {
                                ForEach([24.0,32,48,82],id:\.self) { size in
                                    VStack(spacing:5) {
                                        PreviewAvatar(motif:motif,size:size)
                                        Text("\(Int(size)) pt").font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Text("実験専用アプリ。Liminalogへの採用は未決定です。")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(20)
            }
            .background(light ? ink(0xF2F1F7) : ink(0x111724))
            .navigationTitle("Material study").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement:.topBarTrailing) {
                    Button { light.toggle() } label: { Image(systemName:light ? "moon" : "sun.max") }.accessibilityLabel("背景を切り替える")
                    Button { large.toggle() } label: { Image(systemName:"textformat.size") }.accessibilityLabel("文字サイズを切り替える")
                }
            }
        }.preferredColorScheme(light ? .light : .dark)
            .environment(\.dynamicTypeSize,large ? .accessibility1 : .large)
    }
}
