import SwiftUI

/// 5x7 のドットマトリクス文字。Canvas で丸ドットを描く。
struct DotMatrixText: View {
    private let text: String
    private let glyphs: [[[Bool]]]
    private let dotSize: CGFloat
    private let spacing: CGFloat
    private let color: Color

    init(_ text: String, dotSize: CGFloat = 4, spacing: CGFloat = 1.5, color: Color = Theme.ink) {
        self.text = text
        self.glyphs = text.uppercased().map { DotFont.glyph(for: $0) }
        self.dotSize = dotSize
        self.spacing = spacing
        self.color = color
    }

    private var columns: Int { glyphs.isEmpty ? 0 : glyphs.count * (DotFont.width + 1) - 1 }
    private var pitch: CGFloat { dotSize + spacing }
    private var width: CGFloat { columns == 0 ? 0 : CGFloat(columns) * pitch - spacing }
    private var height: CGFloat { CGFloat(DotFont.height) * pitch - spacing }

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            for (index, glyph) in glyphs.enumerated() {
                let originColumn = index * (DotFont.width + 1)
                for (row, bits) in glyph.enumerated() {
                    for (column, on) in bits.enumerated() where on {
                        path.addEllipse(in: CGRect(
                            x: CGFloat(originColumn + column) * pitch,
                            y: CGFloat(row) * pitch,
                            width: dotSize, height: dotSize))
                    }
                }
            }
            context.fill(path, with: .color(color))
        }
        .frame(width: width, height: height)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: text))
    }
}

enum DotFont {
    static let width = 5
    static let height = 7

    static func glyph(for character: Character) -> [[Bool]] {
        table[character] ?? blank
    }

    private static let blank = Array(repeating: Array(repeating: false, count: width), count: height)

    private static let table: [Character: [[Bool]]] = source.mapValues { rows in
        rows.map { row in row.map { $0 == "#" } }
    }

    private static let source: [Character: [String]] = [
        "0": [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
        "1": ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
        "2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
        "3": ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
        "4": ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
        "5": ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
        "6": ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "],
        "7": ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
        "8": [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
        "9": [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "],
        ":": ["     ", "  #  ", "  #  ", "     ", "  #  ", "  #  ", "     "],
        "-": ["     ", "     ", "     ", " ### ", "     ", "     ", "     "],
        ".": ["     ", "     ", "     ", "     ", "     ", "  #  ", "  #  "],
        "/": ["    #", "    #", "   # ", "  #  ", " #   ", "#    ", "#    "],
        "+": ["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "],
        "A": [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
        "B": ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
        "C": [" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "],
        "D": ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
        "E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
        "F": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
        "G": [" ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ####"],
        "H": ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
        "I": [" ### ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
        "J": ["  ###", "   # ", "   # ", "   # ", "   # ", "#  # ", " ##  "],
        "K": ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
        "L": ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
        "M": ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"],
        "N": ["#   #", "#   #", "##  #", "# # #", "#  ##", "#   #", "#   #"],
        "O": [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
        "P": ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
        "Q": [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"],
        "R": ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
        "S": [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
        "T": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
        "U": ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
        "V": ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
        "W": ["#   #", "#   #", "#   #", "# # #", "# # #", "# # #", " # # "],
        "X": ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"],
        "Y": ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
        "Z": ["#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"],
    ]
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        DotMatrixText("21:00")
        DotMatrixText("10/20 +3", dotSize: 3, spacing: 1)
        DotMatrixText("ATOHA", dotSize: 5, color: Theme.accent)
        DotMatrixText("abc xyz-0.9", dotSize: 2, spacing: 1)
    }
    .padding()
    .background(Theme.paper)
}
