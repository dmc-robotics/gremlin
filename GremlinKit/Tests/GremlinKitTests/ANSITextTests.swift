import Testing
@testable import GremlinKit

struct ANSITextTests {
    @Test func plainTextIsOneUnstyledSegment() {
        #expect(ANSIText.parse("hello") == [ANSISegment(text: "hello", style: ANSIStyle())])
    }

    @Test func colorsAndReset() {
        let segments = ANSIText.parse("a\u{1B}[31mred\u{1B}[0mb")
        #expect(segments.map(\.text) == ["a", "red", "b"])
        #expect(segments[1].style.foreground == .red)
        #expect(segments[2].style == ANSIStyle())
    }

    @Test func combinedCodesStackBoldWithColor() {
        let segment = ANSIText.parse("\u{1B}[1;32mok").first
        #expect(segment?.style.bold == true)
        #expect(segment?.style.foreground == .green)
    }

    @Test func colorsReplaceButStylesStack() {
        let segment = ANSIText.parse("\u{1B}[4m\u{1B}[31m\u{1B}[90mx").first
        #expect(segment?.style.underline == true)
        #expect(segment?.style.foreground == .gray)
    }

    @Test func backgroundColors() {
        #expect(ANSIText.parse("\u{1B}[41mx").first?.style.background == .red)
    }

    @Test func bareEscapeResets() {
        let segments = ANSIText.parse("\u{1B}[1mA\u{1B}[mB")
        #expect(segments[1].style == ANSIStyle())
    }

    @Test func stripsNonSGRSequences() {
        #expect(ANSIText.parse("\u{1B}[?25l\u{1B}[2Kdone\u{1B}[1G\u{1B}[1M").map(\.text) == ["done"])
    }

    @Test func carriageReturnsBecomeNewlinesAndBlankRunsCollapse() {
        #expect(ANSIText.parse("a\r\nb\rc\n\n\n\nd").map(\.text).joined() == "a\nb\nc\n\nd")
    }

    @Test func stripRemovesAllEscapes() {
        #expect(ANSIText.strip("\u{1B}[1;31mError\u{1B}[0m\u{1B}[2K") == "Error")
    }
}
