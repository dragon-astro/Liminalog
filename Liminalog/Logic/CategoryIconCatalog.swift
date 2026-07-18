import Foundation
import UIKit

struct CategoryIconCatalogItem: Identifiable, Hashable, Sendable {
    var id: String { symbol }

    let symbol: String
    let label: String
    let genre: CategoryIconGenre
}

enum CategoryIconGenre: String, CaseIterable, Identifiable, Sendable {
    case study
    case work
    case exercise
    case life
    case food
    case hobby
    case health
    case transport
    case rest
    case social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .study: "学習・思考"
        case .work: "仕事・管理"
        case .exercise: "運動・フィットネス"
        case .life: "家事・生活"
        case .food: "食事・料理"
        case .hobby: "趣味・創作"
        case .health: "健康・セルフケア"
        case .transport: "移動・外出"
        case .rest: "休息・自然"
        case .social: "人・交流"
        }
    }

    var symbol: String {
        switch self {
        case .study: "book.closed.fill"
        case .work: "briefcase.fill"
        case .exercise: "figure.run"
        case .life: "house.fill"
        case .food: "fork.knife"
        case .hobby: "paintpalette.fill"
        case .health: "heart.fill"
        case .transport: "tram.fill"
        case .rest: "moon.fill"
        case .social: "person.2.fill"
        }
    }
}

struct CategoryIconCatalogSection: Identifiable, Sendable {
    var id: CategoryIconGenre { genre }

    let genre: CategoryIconGenre
    let items: [CategoryIconCatalogItem]
}

enum CategoryIconCatalog {
    /// v1以前のCategoryEditSheetで表示していた30候補。編集画面の軽い表側として順序も維持する。
    static let legacySymbols = [
        "book.closed.fill", "graduationcap.fill", "pencil.and.outline",
        "briefcase.fill", "laptopcomputer", "doc.text.fill", "checklist",
        "calendar", "clock.fill", "tram.fill", "figure.walk", "figure.run",
        "airplane", "house.fill", "wrench.and.screwdriver.fill", "cart.fill",
        "fork.knife", "cup.and.saucer.fill", "sparkles", "gamecontroller.fill",
        "music.note", "paintpalette.fill", "camera.fill", "movieclapper.fill",
        "heart.fill", "cross.case.fill", "dumbbell.fill", "bed.double.fill",
        "moon.fill", "person.2.fill",
    ]

    static let items: [CategoryIconCatalogItem] = [
        // 学習・思考
        .init(symbol: "book.closed.fill", label: "読書・学習", genre: .study),
        .init(symbol: "graduationcap.fill", label: "授業・講義", genre: .study),
        .init(symbol: "pencil.and.outline", label: "ノート・執筆", genre: .study),
        .init(symbol: "book.fill", label: "読書", genre: .study),
        .init(symbol: "books.vertical.fill", label: "本棚", genre: .study),
        .init(symbol: "text.book.closed.fill", label: "教科書", genre: .study),
        .init(symbol: "bookmark.fill", label: "ブックマーク", genre: .study),
        .init(symbol: "note.text", label: "メモ", genre: .study),
        .init(symbol: "highlighter", label: "マーカー", genre: .study),
        .init(symbol: "pencil.tip", label: "筆記", genre: .study),
        .init(symbol: "brain.head.profile", label: "思考", genre: .study),
        .init(symbol: "lightbulb.fill", label: "アイデア", genre: .study),
        .init(symbol: "magnifyingglass", label: "調査", genre: .study),
        .init(symbol: "character.book.closed.fill", label: "語学", genre: .study),
        .init(symbol: "textformat", label: "文章", genre: .study),
        .init(symbol: "abc", label: "英語", genre: .study),
        .init(symbol: "function", label: "関数", genre: .study),
        .init(symbol: "sum", label: "計算", genre: .study),
        .init(symbol: "number", label: "数字", genre: .study),
        .init(symbol: "globe", label: "世界・地理", genre: .study),

        // 仕事・管理
        .init(symbol: "briefcase.fill", label: "仕事", genre: .work),
        .init(symbol: "laptopcomputer", label: "PC作業", genre: .work),
        .init(symbol: "doc.text.fill", label: "書類・事務", genre: .work),
        .init(symbol: "checklist", label: "タスク", genre: .work),
        .init(symbol: "calendar", label: "予定", genre: .work),
        .init(symbol: "clock.fill", label: "予定・ルーティン", genre: .work),
        .init(symbol: "desktopcomputer", label: "デスクワーク", genre: .work),
        .init(symbol: "keyboard.fill", label: "入力", genre: .work),
        .init(symbol: "folder.fill", label: "ファイル整理", genre: .work),
        .init(symbol: "tray.full.fill", label: "受信・処理", genre: .work),
        .init(symbol: "archivebox.fill", label: "保管", genre: .work),
        .init(symbol: "printer.fill", label: "印刷", genre: .work),
        .init(symbol: "scanner.fill", label: "スキャン", genre: .work),
        .init(symbol: "paperclip", label: "添付", genre: .work),
        .init(symbol: "link", label: "リンク", genre: .work),
        .init(symbol: "chart.bar.fill", label: "集計", genre: .work),
        .init(symbol: "chart.line.uptrend.xyaxis", label: "分析", genre: .work),
        .init(symbol: "rectangle.and.pencil.and.ellipsis", label: "編集作業", genre: .work),
        .init(symbol: "signature", label: "契約・署名", genre: .work),
        .init(symbol: "list.clipboard.fill", label: "点検リスト", genre: .work),

        // 運動・フィットネス
        .init(symbol: "figure.walk", label: "徒歩", genre: .exercise),
        .init(symbol: "figure.run", label: "ランニング", genre: .exercise),
        .init(symbol: "dumbbell.fill", label: "筋トレ", genre: .exercise),
        .init(symbol: "figure.hiking", label: "ハイキング", genre: .exercise),
        .init(symbol: "figure.strengthtraining.traditional", label: "ウェイト", genre: .exercise),
        .init(symbol: "figure.strengthtraining.functional", label: "機能トレーニング", genre: .exercise),
        .init(symbol: "figure.core.training", label: "体幹", genre: .exercise),
        .init(symbol: "figure.cooldown", label: "クールダウン", genre: .exercise),
        .init(symbol: "figure.flexibility", label: "ストレッチ", genre: .exercise),
        .init(symbol: "figure.yoga", label: "ヨガ", genre: .exercise),
        .init(symbol: "figure.indoor.cycle", label: "室内バイク", genre: .exercise),
        .init(symbol: "figure.outdoor.cycle", label: "サイクリング", genre: .exercise),
        .init(symbol: "figure.open.water.swim", label: "水泳", genre: .exercise),
        .init(symbol: "figure.pool.swim", label: "プール", genre: .exercise),
        .init(symbol: "figure.soccer", label: "サッカー", genre: .exercise),
        .init(symbol: "figure.basketball", label: "バスケ", genre: .exercise),
        .init(symbol: "figure.baseball", label: "野球", genre: .exercise),
        .init(symbol: "figure.tennis", label: "テニス", genre: .exercise),
        .init(symbol: "figure.badminton", label: "バドミントン", genre: .exercise),
        .init(symbol: "figure.golf", label: "ゴルフ", genre: .exercise),

        // 家事・生活
        .init(symbol: "house.fill", label: "家事・生活", genre: .life),
        .init(symbol: "wrench.and.screwdriver.fill", label: "整理・メンテナンス", genre: .life),
        .init(symbol: "cart.fill", label: "買い物", genre: .life),
        .init(symbol: "washer.fill", label: "洗濯", genre: .life),
        .init(symbol: "dishwasher.fill", label: "食器洗い", genre: .life),
        .init(symbol: "dryer.fill", label: "乾燥", genre: .life),
        .init(symbol: "refrigerator.fill", label: "冷蔵庫", genre: .life),
        .init(symbol: "oven.fill", label: "オーブン", genre: .life),
        .init(symbol: "cooktop.fill", label: "コンロ", genre: .life),
        .init(symbol: "microwave.fill", label: "電子レンジ", genre: .life),
        .init(symbol: "sofa.fill", label: "リビング", genre: .life),
        .init(symbol: "lamp.table.fill", label: "照明", genre: .life),
        .init(symbol: "shower.fill", label: "シャワー", genre: .life),
        .init(symbol: "bathtub.fill", label: "入浴", genre: .life),
        .init(symbol: "toilet.fill", label: "トイレ", genre: .life),
        .init(symbol: "basket.fill", label: "洗濯物", genre: .life),
        .init(symbol: "trash.fill", label: "ゴミ出し", genre: .life),
        .init(symbol: "key.fill", label: "戸締まり", genre: .life),
        .init(symbol: "hammer.fill", label: "DIY", genre: .life),
        .init(symbol: "leaf.fill", label: "園芸", genre: .life),

        // 食事・料理
        .init(symbol: "fork.knife", label: "料理・食事", genre: .food),
        .init(symbol: "carrot.fill", label: "野菜", genre: .food),
        .init(symbol: "birthday.cake.fill", label: "お祝い・ケーキ", genre: .food),
        .init(symbol: "takeoutbag.and.cup.and.straw.fill", label: "テイクアウト", genre: .food),
        .init(symbol: "mug.fill", label: "飲み物", genre: .food),
        .init(symbol: "waterbottle.fill", label: "水分補給", genre: .food),
        .init(symbol: "wineglass.fill", label: "お酒", genre: .food),
        .init(symbol: "fish.fill", label: "魚料理", genre: .food),
        .init(symbol: "popcorn.fill", label: "おやつ", genre: .food),
        .init(symbol: "frying.pan.fill", label: "調理", genre: .food),
        .init(symbol: "fork.knife.circle.fill", label: "外食", genre: .food),
        .init(symbol: "takeoutbag.and.cup.and.straw", label: "持ち帰り", genre: .food),
        .init(symbol: "carrot", label: "食材", genre: .food),
        .init(symbol: "birthday.cake", label: "記念日", genre: .food),
        .init(symbol: "waterbottle", label: "ドリンク", genre: .food),
        .init(symbol: "wineglass", label: "ワイン", genre: .food),
        .init(symbol: "fish", label: "魚", genre: .food),
        .init(symbol: "popcorn", label: "映画のお供", genre: .food),
        .init(symbol: "frying.pan", label: "自炊", genre: .food),
        .init(symbol: "mug", label: "コーヒー", genre: .food),

        // 趣味・創作
        .init(symbol: "sparkles", label: "自由時間", genre: .hobby),
        .init(symbol: "gamecontroller.fill", label: "ゲーム", genre: .hobby),
        .init(symbol: "music.note", label: "音楽", genre: .hobby),
        .init(symbol: "paintpalette.fill", label: "創作", genre: .hobby),
        .init(symbol: "camera.fill", label: "写真", genre: .hobby),
        .init(symbol: "movieclapper.fill", label: "動画・鑑賞", genre: .hobby),
        .init(symbol: "headphones", label: "音声・ラジオ", genre: .hobby),
        .init(symbol: "music.mic", label: "歌・カラオケ", genre: .hobby),
        .init(symbol: "guitars.fill", label: "ギター", genre: .hobby),
        .init(symbol: "pianokeys", label: "ピアノ", genre: .hobby),
        .init(symbol: "theatermasks.fill", label: "演劇", genre: .hobby),
        .init(symbol: "film.fill", label: "映画", genre: .hobby),
        .init(symbol: "photo.fill", label: "写真整理", genre: .hobby),
        .init(symbol: "photo.stack.fill", label: "コレクション", genre: .hobby),
        .init(symbol: "paintbrush.fill", label: "絵画", genre: .hobby),
        .init(symbol: "pencil.and.scribble", label: "スケッチ", genre: .hobby),
        .init(symbol: "scissors", label: "手芸", genre: .hobby),
        .init(symbol: "puzzlepiece.fill", label: "パズル", genre: .hobby),
        .init(symbol: "dice.fill", label: "ボードゲーム", genre: .hobby),
        .init(symbol: "tent.fill", label: "キャンプ", genre: .hobby),

        // 健康・セルフケア
        .init(symbol: "heart.fill", label: "ケア", genre: .health),
        .init(symbol: "cross.case.fill", label: "通院・体調", genre: .health),
        .init(symbol: "cross.fill", label: "救護", genre: .health),
        .init(symbol: "stethoscope", label: "診察", genre: .health),
        .init(symbol: "pills.fill", label: "服薬", genre: .health),
        .init(symbol: "pill.fill", label: "サプリ", genre: .health),
        .init(symbol: "bandage.fill", label: "手当て", genre: .health),
        .init(symbol: "syringe.fill", label: "注射", genre: .health),
        .init(symbol: "thermometer.medium", label: "検温", genre: .health),
        .init(symbol: "lungs.fill", label: "呼吸", genre: .health),
        .init(symbol: "brain.fill", label: "メンタル", genre: .health),
        .init(symbol: "waveform.path.ecg", label: "心拍", genre: .health),
        .init(symbol: "waveform.path.ecg.rectangle.fill", label: "健康記録", genre: .health),
        .init(symbol: "facemask.fill", label: "マスク", genre: .health),
        .init(symbol: "allergens.fill", label: "アレルギー", genre: .health),
        .init(symbol: "eye.fill", label: "目のケア", genre: .health),
        .init(symbol: "ear.fill", label: "耳のケア", genre: .health),
        .init(symbol: "figure.mind.and.body", label: "マインドフルネス", genre: .health),
        .init(symbol: "staroflife.fill", label: "医療", genre: .health),
        .init(symbol: "heart.text.square.fill", label: "健診", genre: .health),

        // 移動・外出
        .init(symbol: "tram.fill", label: "電車移動", genre: .transport),
        .init(symbol: "airplane", label: "旅行・遠出", genre: .transport),
        .init(symbol: "car.fill", label: "車", genre: .transport),
        .init(symbol: "bus.fill", label: "バス", genre: .transport),
        .init(symbol: "bicycle", label: "自転車", genre: .transport),
        .init(symbol: "scooter", label: "スクーター", genre: .transport),
        .init(symbol: "ferry.fill", label: "船", genre: .transport),
        .init(symbol: "train.side.front.car", label: "鉄道", genre: .transport),
        .init(symbol: "tram.circle.fill", label: "乗り換え", genre: .transport),
        .init(symbol: "car.side.fill", label: "ドライブ", genre: .transport),
        .init(symbol: "suv.side.fill", label: "遠出・車", genre: .transport),
        .init(symbol: "motorcycle.fill", label: "バイク", genre: .transport),
        .init(symbol: "fuelpump.fill", label: "給油", genre: .transport),
        .init(symbol: "map.fill", label: "地図", genre: .transport),
        .init(symbol: "location.fill", label: "目的地", genre: .transport),
        .init(symbol: "mappin.and.ellipse", label: "場所", genre: .transport),
        .init(symbol: "signpost.right.and.left.fill", label: "道案内", genre: .transport),
        .init(symbol: "suitcase.rolling.fill", label: "旅行準備", genre: .transport),
        .init(symbol: "backpack.fill", label: "お出かけ", genre: .transport),
        .init(symbol: "airplane.departure", label: "出発", genre: .transport),

        // 休息・自然
        .init(symbol: "bed.double.fill", label: "睡眠", genre: .rest),
        .init(symbol: "moon.fill", label: "休息・夜", genre: .rest),
        .init(symbol: "cup.and.saucer.fill", label: "休憩", genre: .rest),
        .init(symbol: "zzz", label: "昼寝", genre: .rest),
        .init(symbol: "alarm.fill", label: "起床", genre: .rest),
        .init(symbol: "timer", label: "小休止", genre: .rest),
        .init(symbol: "hourglass", label: "待ち時間", genre: .rest),
        .init(symbol: "sun.max.fill", label: "日なた", genre: .rest),
        .init(symbol: "sunrise.fill", label: "朝時間", genre: .rest),
        .init(symbol: "sunset.fill", label: "夕暮れ", genre: .rest),
        .init(symbol: "cloud.moon.fill", label: "静かな夜", genre: .rest),
        .init(symbol: "cloud.rain.fill", label: "雨の日", genre: .rest),
        .init(symbol: "wind", label: "外気浴", genre: .rest),
        .init(symbol: "snowflake", label: "涼む", genre: .rest),
        .init(symbol: "chair.lounge.fill", label: "くつろぐ", genre: .rest),
        .init(symbol: "beach.umbrella.fill", label: "休暇", genre: .rest),
        .init(symbol: "water.waves", label: "水辺", genre: .rest),
        .init(symbol: "tree.fill", label: "自然", genre: .rest),
        .init(symbol: "mountain.2.fill", label: "山・景色", genre: .rest),
        .init(symbol: "fireplace.fill", label: "温まる", genre: .rest),

        // 人・交流
        .init(symbol: "person.2.fill", label: "人付き合い", genre: .social),
        .init(symbol: "person.fill", label: "ひとり時間", genre: .social),
        .init(symbol: "person.3.fill", label: "グループ", genre: .social),
        .init(symbol: "person.2.circle.fill", label: "仲間", genre: .social),
        .init(symbol: "bubble.left.fill", label: "チャット", genre: .social),
        .init(symbol: "bubble.left.and.bubble.right.fill", label: "会話", genre: .social),
        .init(symbol: "message.fill", label: "メッセージ", genre: .social),
        .init(symbol: "phone.fill", label: "電話", genre: .social),
        .init(symbol: "video.fill", label: "ビデオ通話", genre: .social),
        .init(symbol: "envelope.fill", label: "メール", genre: .social),
        .init(symbol: "hand.wave.fill", label: "あいさつ", genre: .social),
        .init(symbol: "hands.clap.fill", label: "拍手・応援", genre: .social),
        .init(symbol: "hand.raised.fill", label: "参加・発言", genre: .social),
        .init(symbol: "face.smiling.fill", label: "笑顔", genre: .social),
        .init(symbol: "person.crop.circle.fill", label: "プロフィール", genre: .social),
        .init(symbol: "person.crop.circle.badge.checkmark", label: "連絡確認", genre: .social),
        .init(symbol: "at", label: "SNS", genre: .social),
        .init(symbol: "quote.bubble.fill", label: "相談", genre: .social),
        .init(symbol: "megaphone.fill", label: "告知", genre: .social),
        .init(symbol: "bell.fill", label: "お知らせ", genre: .social),
    ]

    static let sections: [CategoryIconCatalogSection] = CategoryIconGenre.allCases.map { genre in
        CategoryIconCatalogSection(
            genre: genre,
            items: items.filter { $0.genre == genre }
        )
    }

    static let legacyItems: [CategoryIconCatalogItem] = legacySymbols.compactMap { symbol in
        items.first { $0.symbol == symbol }
    }

    static func item(for symbol: String) -> CategoryIconCatalogItem? {
        items.first { $0.symbol == symbol }
    }

    /// 保存済みのカタログ外シンボルも、その端末で解決できる限り変換せず表示する。
    static func displaySymbol(for symbol: String) -> String {
        UIImage(systemName: symbol) == nil ? "questionmark" : symbol
    }

    static func search(_ query: String) -> [CategoryIconCatalogItem] {
        let normalizedQuery = normalizedSearchText(query)
        guard !normalizedQuery.isEmpty else { return items }

        return items.filter { item in
            normalizedSearchText(item.label).contains(normalizedQuery) ||
                normalizedSearchText(item.symbol).contains(normalizedQuery)
        }
    }

    static func normalizedSearchText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "ja_JP")
            )
            .lowercased()
    }
}

enum CategoryIconPinStore {
    static let userDefaultsKey = "category.iconPicker.pinnedSymbols.v1"
    static let defaultSymbols = [
        "book.closed.fill",
        "briefcase.fill",
        "tram.fill",
        "cup.and.saucer.fill",
        "moon.fill",
        "sparkles",
        "gamecontroller.fill",
        "house.fill",
    ]

    static func load(from defaults: UserDefaults = .standard) -> [String] {
        guard defaults.object(forKey: userDefaultsKey) != nil else {
            return defaultSymbols
        }
        guard let stored = defaults.stringArray(forKey: userDefaultsKey) else {
            return defaultSymbols
        }
        return normalized(stored)
    }

    static func save(_ symbols: [String], to defaults: UserDefaults = .standard) {
        defaults.set(normalized(symbols), forKey: userDefaultsKey)
    }

    static func toggled(_ symbol: String, in symbols: [String]) -> [String] {
        var result = normalized(symbols)
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSymbol.isEmpty else { return result }

        if result.contains(normalizedSymbol) {
            result.removeAll { $0 == normalizedSymbol }
        } else {
            result.append(normalizedSymbol)
        }
        return result
    }

    static func normalized(_ symbols: [String]) -> [String] {
        var seen: Set<String> = []
        return symbols.compactMap { rawSymbol in
            let symbol = rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !symbol.isEmpty, seen.insert(symbol).inserted else { return nil }
            return symbol
        }
    }
}
