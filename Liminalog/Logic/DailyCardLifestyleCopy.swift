import Foundation

struct DailyCardLifestyleCopyDraft {
    let title: String
    let messages: [String]
    let symbol: String
}

enum DailyCardLifestyleCopy {
    static let morningPersonaTitles: Set<String> = [
        "朝の短距離走者",
        "早起きコツコツ",
        "朝からせわしない",
        "朝の学習日",
        "朝から動いた日",
        "朝の趣味時間",
        "朝の運動日",
        "朝の生活整備"
    ]

    static let nightPersonaTitles: Set<String> = [
        "夜型スプリンター",
        "宵っ張りの持久型",
        "目まぐるしい夜",
        "丑三つの天才",
        "不眠の修行僧",
        "体内時計バグり気味",
        "夜の学習日",
        "夜まで動いた日",
        "夜の趣味時間",
        "夜の運動日",
        "夜の生活整備"
    ]

    static func shapeDraft(analysis: DailyCardPatternDetector) -> DailyCardLifestyleCopyDraft? {
        guard let focus = analysis.focusCategory,
              focus.category.analysisKind != .unspecified else {
            return nil
        }

        let category = focus.category
        let name = displayName(for: category)
        let duration = formatDuration(focus.duration)
        let switchCount = max(analysis.meaningfulSwitchCount, 1)
        let title = shapeTitle(
            kind: category.analysisKind,
            chronotype: analysis.chronotype,
            shape: analysis.shape
        )

        return DailyCardLifestyleCopyDraft(
            title: title,
            messages: shapeMessages(
                kind: category.analysisKind,
                name: name,
                duration: duration,
                switchCount: switchCount,
                shape: analysis.shape
            ),
            symbol: shapeSymbol(kind: category.analysisKind, shape: analysis.shape)
        )
    }

    static func firstRecordDraft(for category: Category) -> DailyCardLifestyleCopyDraft? {
        let name = displayName(for: category)
        switch category.analysisKind {
        case .unspecified:
            return nil
        case .study:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、学習デビュー",
                messages: [
                    "\(name)が初登場。今日は学ぶ時間の地図に新しいピンが増えた。",
                    "\(name)を初めて記録。これから見返せる学習ログがひとつ生まれた。"
                ],
                symbol: "sparkles"
            )
        case .work:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、稼働開始",
                messages: [
                    "\(name)が初登場。仕事として動いた時間が、今日から記録に残りはじめた。",
                    "\(name)を初めて記録。自分の稼働パターンを見る材料がひとつ増えた。"
                ],
                symbol: "sparkles"
            )
        case .hobbyPlay:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、好きなこと初登場",
                messages: [
                    "\(name)が初登場。好きなことに使った時間も、ちゃんと今日の色になった。",
                    "\(name)を初めて記録。遊びや趣味の輪郭が少し見えやすくなった。"
                ],
                symbol: "sparkles"
            )
        case .exercise:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、運動デビュー",
                messages: [
                    "\(name)が初登場。体を動かした時間が、今日のログにしっかり残った。",
                    "\(name)を初めて記録。運動のリズムを見ていく入口ができた。"
                ],
                symbol: "sparkles"
            )
        case .household:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、生活整備デビュー",
                messages: [
                    "\(name)が初登場。生活を整えた時間が、今日のカードに残った。",
                    "\(name)を初めて記録。暮らしを支える動きも見えるようになった。"
                ],
                symbol: "sparkles"
            )
        case .sleep:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、回復記録はじめ",
                messages: [
                    "\(name)が初登場。休む時間も、今日の大事なログとして残った。",
                    "\(name)を初めて記録。回復の取り方を見返す材料が増えた。"
                ],
                symbol: "sparkles"
            )
        }
    }

    static func returnAfterGapDraft(for category: Category, days: Int) -> DailyCardLifestyleCopyDraft? {
        let name = displayName(for: category)
        switch category.analysisKind {
        case .unspecified:
            return nil
        case .study:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、学習再開",
                messages: [
                    "\(name)が\(days)日ぶりに復帰。止まっていた学習ログがまた動き出した。",
                    "\(days)日ぶりの\(name)。今日は学ぶ時間をもう一度拾い直せた。"
                ],
                symbol: "hand.wave.fill"
            )
        case .work:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、稼働再開",
                messages: [
                    "\(name)が\(days)日ぶりに復帰。仕事の流れにもう一度手が入った。",
                    "\(days)日ぶりの\(name)。止まっていた稼働ログが今日またつながった。"
                ],
                symbol: "hand.wave.fill"
            )
        case .hobbyPlay:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、趣味再開",
                messages: [
                    "\(name)が\(days)日ぶりに復帰。好きなことの時間が今日また戻ってきた。",
                    "\(days)日ぶりの\(name)。忙しさの中に、遊びの色がひとつ戻った。"
                ],
                symbol: "hand.wave.fill"
            )
        case .exercise:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、運動再開",
                messages: [
                    "\(name)が\(days)日ぶりに復帰。体を動かす流れが今日また戻った。",
                    "\(days)日ぶりの\(name)。運動の記録が途切れっぱなしにならずに済んだ。"
                ],
                symbol: "hand.wave.fill"
            )
        case .household:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、生活整備再開",
                messages: [
                    "\(name)が\(days)日ぶりに復帰。暮らしを整える動きが今日また入った。",
                    "\(days)日ぶりの\(name)。生活の土台に手を戻せた日。"
                ],
                symbol: "hand.wave.fill"
            )
        case .sleep:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、回復再開",
                messages: [
                    "\(name)が\(days)日ぶりに復帰。休む時間をまた記録に戻せた。",
                    "\(days)日ぶりの\(name)。回復の取り方を見返せる日が増えた。"
                ],
                symbol: "hand.wave.fill"
            )
        }
    }

    static func personalBestDraft(
        for category: Category,
        duration: TimeInterval,
        improvement: TimeInterval
    ) -> DailyCardLifestyleCopyDraft? {
        let name = displayName(for: category)
        let durationText = formatDuration(duration)
        let improvementText = formatDuration(improvement)
        switch category.analysisKind {
        case .unspecified:
            return nil
        case .study:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、学習自己最長",
                messages: [
                    "\(name)が\(durationText)で自己最長。学ぶ時間が前回ベストより\(improvementText)伸びた。",
                    "\(name)の学習ログを更新。今日は\(durationText)、かなり腰を据えて向き合った。"
                ],
                symbol: "crown.fill"
            )
        case .work:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、稼働自己最長",
                messages: [
                    "\(name)が\(durationText)で自己最長。仕事に向かった時間が前回より\(improvementText)伸びた。",
                    "\(name)の稼働ログを更新。今日は\(durationText)、長めに走り切った。"
                ],
                symbol: "crown.fill"
            )
        case .hobbyPlay:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、趣味自己最長",
                messages: [
                    "\(name)が\(durationText)で自己最長。好きなことに使った時間が前回より\(improvementText)伸びた。",
                    "\(name)の趣味ログを更新。今日は\(durationText)、ちゃんと楽しむ側に時間を使った。"
                ],
                symbol: "crown.fill"
            )
        case .exercise:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、運動自己最長",
                messages: [
                    "\(name)が\(durationText)で自己最長。体を動かした時間が前回より\(improvementText)伸びた。",
                    "\(name)の運動ログを更新。今日は\(durationText)、体を使う日にできた。"
                ],
                symbol: "crown.fill"
            )
        case .household:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、整備自己最長",
                messages: [
                    "\(name)が\(durationText)で自己最長。生活を整える時間が前回より\(improvementText)伸びた。",
                    "\(name)の生活整備ログを更新。今日は\(durationText)、暮らしの土台に手を入れた。"
                ],
                symbol: "crown.fill"
            )
        case .sleep:
            return DailyCardLifestyleCopyDraft(
                title: "\(name)、回復自己最長",
                messages: [
                    "\(name)が\(durationText)で自己最長。休む時間が前回より\(improvementText)伸びた。",
                    "\(name)の回復ログを更新。今日は\(durationText)、休む側にしっかり振れた。"
                ],
                symbol: "crown.fill"
            )
        }
    }

    static func fallbackDraft(
        for snapshot: DailyScoreSnapshot,
        primaryCategory: Category?
    ) -> DailyCardLifestyleCopyDraft {
        let title = fallbackTitle(for: snapshot, primaryCategory: primaryCategory)
        let message = fallbackMessage(for: snapshot, primaryCategory: primaryCategory)
        let symbol = fallbackSymbol(for: snapshot)
        return DailyCardLifestyleCopyDraft(title: title, messages: [message], symbol: symbol)
    }

    private static func shapeTitle(
        kind: CategoryAnalysisKind,
        chronotype: DailyCardPatternDetector.Chronotype,
        shape: DailyCardPatternDetector.Shape
    ) -> String {
        switch kind {
        case .study:
            if chronotype == .morning { return "朝の学習日" }
            if chronotype == .evening || chronotype == .midnight { return "夜の学習日" }
            return shape == .sprinter ? "集中して学んだ日" : "学習が進んだ日"
        case .work:
            if chronotype == .morning { return "朝から動いた日" }
            if chronotype == .evening || chronotype == .midnight { return "夜まで動いた日" }
            return shape == .sprinter ? "仕事集中の日" : "仕事が進んだ日"
        case .hobbyPlay:
            if chronotype == .morning { return "朝の趣味時間" }
            if chronotype == .evening || chronotype == .midnight { return "夜の趣味時間" }
            return shape == .sprinter ? "好きなこと集中日" : "好きなことをした日"
        case .exercise:
            if chronotype == .morning { return "朝の運動日" }
            if chronotype == .evening || chronotype == .midnight { return "夜の運動日" }
            return shape == .zapping ? "運動で切り替えた日" : "体を動かした日"
        case .household:
            if chronotype == .morning { return "朝の生活整備" }
            if chronotype == .evening || chronotype == .midnight { return "夜の生活整備" }
            return "生活を整えた日"
        case .sleep:
            return "回復に寄せた日"
        case .unspecified:
            return "記録が残った日"
        }
    }

    private static func shapeMessages(
        kind: CategoryAnalysisKind,
        name: String,
        duration: String,
        switchCount: Int,
        shape: DailyCardPatternDetector.Shape
    ) -> [String] {
        switch kind {
        case .study:
            return [
                "\(name)に\(duration)。今日は学ぶ時間がはっきり残った。",
                shape == .zapping
                    ? "\(name)を含めて\(switchCount)回切り替え。細かく動きながらも学習の足跡は残った。"
                    : "\(name)を中心に進めた日。あとから見ても、何に時間を使ったかがわかりやすい。"
            ]
        case .work:
            return [
                "\(name)に\(duration)。仕事として動いた時間が今日の軸になった。",
                shape == .sprinter
                    ? "\(name)を長めに確保。稼働の中心がかなりはっきりした日。"
                    : "\(name)を含めて仕事の流れが残った日。積み上げ方があとから見える。"
            ]
        case .hobbyPlay:
            return [
                "\(name)に\(duration)。好きなことに使った時間が今日の色になった。",
                shape == .zapping
                    ? "\(switchCount)回切り替えながら、\(name)の時間もちゃんと入った。"
                    : "\(name)を中心に、遊びや趣味の時間を確保できた日。"
            ]
        case .exercise:
            return [
                "\(name)に\(duration)。体を動かした時間が今日の記録に残った。",
                shape == .zapping
                    ? "\(name)で流れを切り替えた日。動く時間が一日のリズムを作った。"
                    : "\(name)を入れたことで、運動した日として見返せる。"
            ]
        case .household:
            return [
                "\(name)に\(duration)。生活を整える時間が今日の土台になった。",
                "\(name)を記録。暮らしを支える動きが、ちゃんと見える形で残った。"
            ]
        case .sleep:
            return [
                "\(name)に\(duration)。回復に使った時間が今日の中心に残った。",
                "\(name)を記録。休み方を見返すための手がかりが増えた。"
            ]
        case .unspecified:
            return ["\(name)に\(duration)。今日のログがひとつ残った。"]
        }
    }

    private static func shapeSymbol(
        kind: CategoryAnalysisKind,
        shape: DailyCardPatternDetector.Shape
    ) -> String {
        switch kind {
        case .study:
            return "book.closed.fill"
        case .work:
            return "briefcase.fill"
        case .hobbyPlay:
            return "sparkles"
        case .exercise:
            return "figure.run"
        case .household:
            return "house.fill"
        case .sleep:
            return "moon.zzz.fill"
        case .unspecified:
            return shape == .sprinter ? "bolt.fill" : "sparkle.magnifyingglass"
        }
    }

    private static func fallbackTitle(
        for snapshot: DailyScoreSnapshot,
        primaryCategory: Category?
    ) -> String {
        if snapshot.firstRecordDay, let primaryCategory {
            return firstRecordDraft(for: primaryCategory)?.title ?? "はじめた日"
        }
        if snapshot.personalBestDay, let primaryCategory {
            return personalBestTitle(for: primaryCategory) ?? "自己ベストの日"
        }
        if snapshot.returnAfterGapDay, let primaryCategory {
            return returnTitle(for: primaryCategory) ?? "戻ってきた日"
        }
        if snapshot.planMatchedDay || (snapshot.plannedDuration > 0 && snapshot.score >= 88) {
            return primaryCategory?.analysisKind == .unspecified ? "予定通りの日" : "予定通り進んだ日"
        }
        if snapshot.chargeDay {
            return "回復に寄せた日"
        }
        if snapshot.focusedDay, let primaryCategory {
            return focusedFallbackTitle(for: primaryCategory)
        }
        if snapshot.balancedDay {
            return "マルチ活動の日"
        }
        if let primaryCategory, primaryCategory.analysisKind != .unspecified {
            return baseFallbackTitle(for: primaryCategory)
        }
        if snapshot.recordedDuration >= 45 * 60 {
            return "記録が残った日"
        }
        if snapshot.plannedDuration > 0 {
            return "予定を置いた日"
        }
        return "小さな記録の日"
    }

    private static func fallbackMessage(
        for snapshot: DailyScoreSnapshot,
        primaryCategory: Category?
    ) -> String {
        guard let primaryCategory, snapshot.recordedDuration > 0 else {
            if snapshot.plannedDuration > 0, snapshot.recordedDuration <= 0 {
                return "予定だけが残っている日"
            }
            if snapshot.recordedDuration > 0 {
                return "記録から復元したカード"
            }
            return "その日のログから作ったカード"
        }

        let name = displayName(for: primaryCategory)
        switch primaryCategory.analysisKind {
        case .study:
            return "\(name)を中心に学習時間が残った日。何を学んだかがあとから見返しやすい。"
        case .work:
            return "\(name)を中心に仕事の時間が残った日。稼働の軸が見えるカード。"
        case .hobbyPlay:
            return "\(name)を中心に趣味や遊びの時間が残った日。好きなことの色が出ている。"
        case .exercise:
            return "\(name)を中心に体を動かした日。運動の記録として見返せる。"
        case .household:
            return "\(name)を中心に生活を整えた日。暮らしの土台に手を入れた記録。"
        case .sleep:
            return "\(name)を中心に回復へ寄せた日。休み方の手がかりが残っている。"
        case .unspecified:
            return "\(name)を中心に過ごした日"
        }
    }

    private static func personalBestTitle(for category: Category) -> String? {
        switch category.analysisKind {
        case .unspecified:
            return nil
        case .study:
            return "\(displayName(for: category))、学習自己最長"
        case .work:
            return "\(displayName(for: category))、稼働自己最長"
        case .hobbyPlay:
            return "\(displayName(for: category))、趣味自己最長"
        case .exercise:
            return "\(displayName(for: category))、運動自己最長"
        case .household:
            return "\(displayName(for: category))、整備自己最長"
        case .sleep:
            return "\(displayName(for: category))、回復自己最長"
        }
    }

    private static func returnTitle(for category: Category) -> String? {
        switch category.analysisKind {
        case .unspecified:
            return nil
        case .study:
            return "\(displayName(for: category))、学習再開"
        case .work:
            return "\(displayName(for: category))、稼働再開"
        case .hobbyPlay:
            return "\(displayName(for: category))、趣味再開"
        case .exercise:
            return "\(displayName(for: category))、運動再開"
        case .household:
            return "\(displayName(for: category))、生活整備再開"
        case .sleep:
            return "\(displayName(for: category))、回復再開"
        }
    }

    private static func focusedFallbackTitle(for category: Category) -> String {
        switch category.analysisKind {
        case .study:
            return "集中して学んだ日"
        case .work:
            return "仕事集中の日"
        case .hobbyPlay:
            return "好きなこと集中日"
        case .exercise:
            return "体を動かした日"
        case .household:
            return "生活を整えた日"
        case .sleep:
            return "回復に寄せた日"
        case .unspecified:
            return "集中した日"
        }
    }

    private static func baseFallbackTitle(for category: Category) -> String {
        switch category.analysisKind {
        case .study:
            return "学習が進んだ日"
        case .work:
            return "仕事が進んだ日"
        case .hobbyPlay:
            return "好きなことをした日"
        case .exercise:
            return "体を動かした日"
        case .household:
            return "生活を整えた日"
        case .sleep:
            return "回復に寄せた日"
        case .unspecified:
            return "記録が残った日"
        }
    }

    private static func fallbackSymbol(for snapshot: DailyScoreSnapshot) -> String {
        if snapshot.firstRecordDay {
            return "sparkles"
        }
        if snapshot.personalBestDay {
            return "crown.fill"
        }
        if snapshot.returnAfterGapDay {
            return "hand.wave.fill"
        }
        if snapshot.planMatchedDay || (snapshot.plannedDuration > 0 && snapshot.score >= 88) {
            return "checkmark.seal.fill"
        }
        if snapshot.chargeDay {
            return "battery.100percent"
        }
        if snapshot.focusedDay {
            return "scope"
        }
        if snapshot.balancedDay {
            return "circle.hexagongrid.fill"
        }
        if snapshot.plannedDuration <= 0 {
            return "pencil.and.list.clipboard"
        }
        return "sparkle.magnifyingglass"
    }

    private static func displayName(for category: Category) -> String {
        category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? category.analysisKind.title
            : category.name
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int(seconds / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return "\(hours)時間\(minutes)分"
        } else if hours > 0 {
            return "\(hours)時間"
        } else {
            return "\(minutes)分"
        }
    }
}
