import Foundation

enum DiffOperation {
    case equal(String)
    case insert(String)
    case delete(String)
}

struct DiffHunk {
    let operation: DiffOperation

    var line: String {
        switch operation {
        case .equal(let s), .insert(let s), .delete(let s): return s
        }
    }
}

struct DiffEngine {

    static let maxLines = 500

    static func diff(old: String, new: String) -> [DiffHunk] {
        let rawA = old.components(separatedBy: .newlines)
        let rawB = new.components(separatedBy: .newlines)
        let a = rawA.count > maxLines ? Array(rawA[..<maxLines]) : rawA
        let b = rawB.count > maxLines ? Array(rawB[..<maxLines]) : rawB
        return diffLines(a, b)
    }

    private static func diffLines(_ a: [String], _ b: [String]) -> [DiffHunk] {
        let n = a.count
        let m = b.count

        if n == 0 { return b.map { DiffHunk(operation: .insert($0)) } }
        if m == 0 { return a.map { DiffHunk(operation: .delete($0)) } }

        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var hunks: [DiffHunk] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i - 1] == b[j - 1] {
                hunks.append(DiffHunk(operation: .equal(a[i - 1])))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                hunks.append(DiffHunk(operation: .insert(b[j - 1])))
                j -= 1
            } else {
                hunks.append(DiffHunk(operation: .delete(a[i - 1])))
                i -= 1
            }
        }
        return hunks.reversed()
    }
}
