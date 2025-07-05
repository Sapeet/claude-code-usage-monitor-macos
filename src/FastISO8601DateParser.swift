import Foundation

enum FastISO8601DateParser {
    static func parse(_ string: String) -> Date? {
        // ISO8601形式: "2025-07-04T12:34:56.789Z" または "2025-07-04T12:34:56Z"
        guard string.count >= 20 else { return nil }
        
        let chars = Array(string)
        
        // 年月日時分秒の数値を直接パース
        guard chars[4] == "-" && chars[7] == "-" && chars[10] == "T" &&
              chars[13] == ":" && chars[16] == ":" else { return nil }
        
        // 数値を高速に変換（文字コードから直接計算）
        func twoDigits(at index: Int) -> Int? {
            let c1 = chars[index].asciiValue, c2 = chars[index + 1].asciiValue
            guard let c1, let c2, c1 >= 48 && c1 <= 57, c2 >= 48 && c2 <= 57 else { return nil }
            return Int(c1 - 48) * 10 + Int(c2 - 48)
        }
        
        func fourDigits(at index: Int) -> Int? {
            let c1 = chars[index].asciiValue, c2 = chars[index + 1].asciiValue
            let c3 = chars[index + 2].asciiValue, c4 = chars[index + 3].asciiValue
            guard let c1, let c2, let c3, let c4,
                  c1 >= 48 && c1 <= 57, c2 >= 48 && c2 <= 57,
                  c3 >= 48 && c3 <= 57, c4 >= 48 && c4 <= 57 else { return nil }
            return Int(c1 - 48) * 1000 + Int(c2 - 48) * 100 + Int(c3 - 48) * 10 + Int(c4 - 48)
        }
        
        guard let year = fourDigits(at: 0),
              let month = twoDigits(at: 5),
              let day = twoDigits(at: 8),
              let hour = twoDigits(at: 11),
              let minute = twoDigits(at: 14),
              let second = twoDigits(at: 17) else { return nil }
        
        // 小数秒の処理
        var nanoseconds = 0
        var endIndex = 19
        
        if chars.count > 19 && chars[19] == "." {
            endIndex = 20
            var multiplier = 100_000_000
            while endIndex < chars.count && chars[endIndex].isNumber {
                if let digit = chars[endIndex].asciiValue {
                    nanoseconds += Int(digit - 48) * multiplier
                    multiplier /= 10
                }
                endIndex += 1
                if multiplier == 0 { break }
            }
        }
        
        // タイムゾーンの確認（"Z" または "+00:00" など）
        guard endIndex < chars.count && (chars[endIndex] == "Z" || chars[endIndex] == "+" || chars[endIndex] == "-") else { return nil }
        
        // DateComponentsを使ってDateを作成
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanoseconds
        components.timeZone = TimeZone(secondsFromGMT: 0)
        
        return Calendar(identifier: .gregorian).date(from: components)
    }
}