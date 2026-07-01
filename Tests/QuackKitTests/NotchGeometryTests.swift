import Testing
import CoreGraphics
@testable import QuackKit

@Suite struct NotchGeometryTests {

    // A 1512-wide built-in screen (14" MBP logical width) with 180pt of notch
    // flanked by two auxiliary areas.
    private let screenMinX: CGFloat = 0
    private let screenWidth: CGFloat = 1512

    @Test func notchSpanSitsBetweenTheAuxiliaryAreas() {
        let span = NotchGeometry.notchSpan(
            screenMinX: screenMinX, screenWidth: screenWidth,
            leftAuxWidth: 666, rightAuxWidth: 666
        )
        #expect(span?.minX == 666)
        #expect(span?.maxX == 846)          // 1512 - 666
        #expect(span?.width == 180)
    }

    @Test func notchSpanRespectsScreenOrigin() {
        // A built-in screen positioned to the right of an external display.
        let span = NotchGeometry.notchSpan(
            screenMinX: 1920, screenWidth: 1512,
            leftAuxWidth: 666, rightAuxWidth: 666
        )
        #expect(span?.minX == 2586)         // 1920 + 666
        #expect(span?.maxX == 2766)         // 1920 + 1512 - 666
    }

    @Test func noNotchWhenAuxiliaryWidthsAreZero() {
        #expect(NotchGeometry.notchSpan(
            screenMinX: 0, screenWidth: 1920,
            leftAuxWidth: 0, rightAuxWidth: 0
        ) == nil)
    }

    @Test func noNotchWhenOnlyOneAuxiliarySideIsPresent() {
        #expect(NotchGeometry.notchSpan(
            screenMinX: 0, screenWidth: 1512,
            leftAuxWidth: 666, rightAuxWidth: 0
        ) == nil)
    }

    @Test func crushedItemsAreThoseWhoseMidpointFallsUnderTheNotch() {
        let span = NotchGeometry.notchSpan(
            screenMinX: 0, screenWidth: 1512,
            leftAuxWidth: 666, rightAuxWidth: 666
        )!
        // visible: midX 900 (right of notch)
        let visible = StatusItemFrame(ownerPID: 1, windowID: 10,
            frame: CGRect(x: 884, y: 0, width: 32, height: 24))   // midX 900
        // crushed: midX 756 (inside 666...846)
        let crushed = StatusItemFrame(ownerPID: 2, windowID: 11,
            frame: CGRect(x: 740, y: 0, width: 32, height: 24))   // midX 756
        let result = NotchGeometry.crushedItems([visible, crushed], notch: span)
        #expect(result == [crushed])
    }

    @Test func itemExactlyOnTheNotchEdgeCountsAsCrushed() {
        let span = NotchGeometry.NotchSpan(minX: 666, maxX: 846)
        let onEdge = StatusItemFrame(ownerPID: 3, windowID: 12,
            frame: CGRect(x: 650, y: 0, width: 32, height: 24))   // midX 666 == minX
        #expect(NotchGeometry.crushedItems([onEdge], notch: span) == [onEdge])
    }

    @Test func emptyInputYieldsEmptyOutput() {
        let span = NotchGeometry.NotchSpan(minX: 666, maxX: 846)
        #expect(NotchGeometry.crushedItems([], notch: span).isEmpty)
    }
}
