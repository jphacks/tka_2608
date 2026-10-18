import Foundation

/// 納得度の採点の厳しさ（1〜10、実験用）。指示文のうち厳しさで変わる部分だけを持つ。
/// 2は draft-03-app2 の指示と同じ文面になる（追加の規則・例なし）
struct Strictness {
    /// しきい値以上の帯の説明
    var band: String
    /// 1通目から提案してよいか
    var first: String
    /// 追加の規則（改行から始める。なければ空）
    var rule = ""
    /// 「ゼミの集合場所がDMで届くから確認したい」への納得度／action／秒／返答
    var contactExample = "80／proposeUnlock／120／「集合場所の確認は大事だね。2分で確認したら、やることに戻ろう。」"
    /// 「30分集中したから、5分だけ動画で休憩したい」への納得度／action／秒／返答
    var breakExample: String
    /// やることを口実にした例（改行から始める。なければ空）
    var pretextExample = ""

    static func level(_ level: Int, threshold t: Int) -> Strictness {
        let below = t - 1
        let band = "今そのアプリを使う具体的な必要があり、使う範囲がはっきりしている。"
        let first = "具体的な必要性があれば、1通目から利用を提案してかまいません。"
        // 「やることの前に少しだけ」と言われたときの例（Issue: 仕事に反応して納得度が上がる）
        func pretext(_ score: Int, _ action: String, _ reply: String) -> String {
            "\n「ちょっと仕事をする前に2分だけ」→\(score)／\(action)／null／「\(reply)」"
        }
        let noPretext = "やることに触れた、利用後にやると言った、「少しだけ」「すぐ戻る」と言ったことだけでは加点しません。"
        let breakNeedsRecord = "休憩は、すでに取り組んだ内容と時間が具体的なときだけ認めます。"
        let contactAsk = "65／ask／null／「集合場所の確認なんだね。集合はいつごろかな？」"
        switch min(max(level, 1), 10) {
        case 1:
            return Strictness(
                band: "今そのアプリを使う理由があり、時間を区切るつもりがある。気分転換や短い息抜きも含みます。",
                first: "理由が伝われば、1通目から利用を提案してかまいません。",
                rule: "\n【厳しさ1/10】気持ちを尊重し、疑いすぎません。目的が語られ、短時間で戻るつもりがあれば利用を提案します。",
                contactExample: "90／proposeUnlock／120／「集合場所の確認は大事だね。2分で確認したら、やることに戻ろう。」",
                breakExample: "90／proposeUnlock／300／「しっかり進めたね。5分休んだら、また続きをやろう。」",
                pretextExample: pretext(80, "proposeUnlock", "仕事の前のひと息だね。2分で切り上げて、仕事に取りかかろう。"))
        case 2:
            return Strictness(
                band: band + "時間を区切った具体的な休憩も含みます。",
                first: first,
                breakExample: "75／proposeUnlock／300／「しっかり進めたね。5分休んだら、また続きをやろう。」")
        case 3:
            return Strictness(
                band: band + "時間を区切った具体的な休憩も含みます。",
                first: first,
                rule: "\n【厳しさ3/10】\(noPretext)",
                breakExample: "\(t)／proposeUnlock／300／「しっかり進めたね。5分休んだら、また続きをやろう。」",
                pretextExample: pretext(60, "ask", "仕事の前に見たくなったんだね。何を見たいのか教えてくれる？"))
        case 4:
            return Strictness(
                band: band + "時間を区切った具体的な休憩も含みます。",
                first: first,
                rule: "\n【厳しさ4/10】\(noPretext)\(breakNeedsRecord)",
                breakExample: "\(t)／proposeUnlock／300／「しっかり進めたね。5分休んだら、また続きをやろう。」",
                pretextExample: pretext(50, "ask", "仕事の前に見たくなったんだね。今見ないと困ることがあるのかな？"))
        case 5:
            return Strictness(
                band: band + "利用後の行動も具体的で、時間を区切った休憩も含みます。",
                first: first,
                rule: "\n【厳しさ5/10】\(noPretext)\(breakNeedsRecord)判断に迷ったら\(below)以下にします。",
                breakExample: "\(t)／proposeUnlock／300／「しっかり進めたね。5分休んだら、また続きをやろう。」",
                pretextExample: pretext(40, "suggestFocus", "先に仕事を5分だけ始めてみない？区切りがついたら考えよう。"))
        case 6:
            return Strictness(
                band: band + "利用後の行動も具体的で、取り組んだ実績のある休憩も含みます。",
                first: "1通目は、連絡や予定の確認など用事がはっきりしているときだけ利用を提案します。",
                rule: "\n【厳しさ6/10】\(noPretext)\(breakNeedsRecord)暇つぶし・娯楽が目的なら\(below)以下です。判断に迷ったら\(below)以下にします。",
                breakExample: "\(t)／proposeUnlock／300／「しっかり進めたね。5分休んだら、また続きをやろう。」",
                pretextExample: pretext(35, "suggestFocus", "先に仕事を5分だけ始めてみない？区切りがついたら考えよう。"))
        case 7:
            return Strictness(
                band: "今そのアプリを使わないと困る用事（連絡の見逃し、予定に遅れる等）があり、使う範囲がはっきりしている。",
                first: "1通目は、連絡や予定の確認など用事がはっきりしているときだけ利用を提案します。",
                rule: "\n【厳しさ7/10】\(noPretext)休憩・気分転換・娯楽は、実績が具体的でも70以下です。判断に迷ったら\(below)以下にします。",
                breakExample: "70／suggestFocus／null／「しっかり進めたね。アプリを開かずに少し体を伸ばしてから続きをやろう。」",
                pretextExample: pretext(30, "suggestFocus", "先に仕事を5分だけ始めてみない？区切りがついたら考えよう。"))
        case 8:
            return Strictness(
                band: "今そのアプリを使わないと困る用事があり、内容・使う範囲・利用後の行動を具体的に説明できている。",
                first: "1通目では\(below)以下にし、事情を確かめます。",
                rule: "\n【厳しさ8/10】\(noPretext)休憩・気分転換・娯楽は60以下です。あとで確認しても困らない用事は\(below)以下です。",
                contactExample: contactAsk,
                breakExample: "60／suggestFocus／null／「しっかり進めたね。アプリを開かずに少し体を伸ばしてから続きをやろう。」",
                pretextExample: pretext(20, "suggestFocus", "先に仕事を始めよう。区切りがついたら、また相談してね。"))
        case 9:
            return Strictness(
                band: "期限が迫った連絡や予定の確認など、今すぐでないと困る用事で、内容と使う範囲を具体的に説明できている。",
                first: "1通目では\(below)以下にし、事情を確かめます。",
                rule: "\n【厳しさ9/10】\(noPretext)休憩・気分転換・娯楽は40以下です。あとで確認しても困らない用事、通知や別の手段で済む用事は\(below)以下です。",
                contactExample: contactAsk,
                breakExample: "40／suggestFocus／null／「しっかり進めたね。アプリを開かずに少し体を伸ばしてから続きをやろう。」",
                pretextExample: pretext(15, "suggestFocus", "先に仕事を始めよう。区切りがついたら、また相談してね。"))
        default:
            return Strictness(
                band: "緊急の連絡の確認など、今このアプリを使わないと明確に困る場合だけ。",
                first: "1〜2通目では\(below)以下にし、事情を確かめます。",
                rule: "\n【厳しさ10/10】原則として使わない方向で考えます。\(noPretext)休憩・気分転換・娯楽・暇つぶしは20以下です。あとで確認しても困らない用事、通知や別の手段で済む用事は\(below)以下です。",
                contactExample: contactAsk,
                breakExample: "20／suggestFocus／null／「しっかり進めたね。アプリを開かずに少し体を伸ばしてから続きをやろう。」",
                pretextExample: pretext(10, "suggestFocus", "先に仕事を始めよう。区切りがついたら、また相談してね。"))
        }
    }
}
