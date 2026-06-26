import Testing
import CoreGraphics
@testable import QuackKit

@Suite struct ScreenGeometryTests {
    private let left = ScreenInfo(id: "left", frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
    private let right = ScreenInfo(id: "right", frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
    private var screens: [ScreenInfo] { [left, right] }

    @Test func screenContainingPoint() {
        #expect(ScreenGeometry.screen(containing: CGPoint(x: 500, y: 400), in: screens)?.id == "left")
        #expect(ScreenGeometry.screen(containing: CGPoint(x: 1500, y: 400), in: screens)?.id == "right")
    }

    @Test func screenForPointInGapFallsBackToNearest() {
        #expect(ScreenGeometry.screen(containing: CGPoint(x: 1400, y: 5000), in: screens)?.id == "right")
    }

    @Test func adjacentRight() {
        #expect(ScreenGeometry.adjacentScreen(from: left, direction: .right, in: screens)?.id == "right")
    }

    @Test func adjacentLeft() {
        #expect(ScreenGeometry.adjacentScreen(from: right, direction: .left, in: screens)?.id == "left")
    }

    @Test func noAdjacentInDirection() {
        #expect(ScreenGeometry.adjacentScreen(from: left, direction: .left, in: screens) == nil)
        #expect(ScreenGeometry.adjacentScreen(from: left, direction: .up, in: screens) == nil)
    }

    @Test func directionFromDelta() {
        #expect(ScreenGeometry.direction(forDelta: CGVector(dx: 120, dy: 10), minMagnitude: 50) == .right)
        #expect(ScreenGeometry.direction(forDelta: CGVector(dx: -120, dy: 10), minMagnitude: 50) == .left)
        #expect(ScreenGeometry.direction(forDelta: CGVector(dx: 5, dy: -120), minMagnitude: 50) == .up)
        #expect(ScreenGeometry.direction(forDelta: CGVector(dx: 10, dy: 10), minMagnitude: 50) == nil)
    }

    @Test func repositionPreservesRelativePosition() {
        let win = CGRect(x: 100, y: 80, width: 300, height: 200)   // 10% into left screen
        let moved = ScreenGeometry.reposition(windowFrame: win, from: left, to: right)
        #expect(abs(moved.minX - 1100) < 0.5)
        #expect(abs(moved.minY - 80) < 0.5)
        #expect(moved.size == win.size)
    }

    @Test func repositionClampsToStayOnScreen() {
        let win = CGRect(x: 900, y: 700, width: 300, height: 200)
        let moved = ScreenGeometry.reposition(windowFrame: win, from: left, to: right)
        #expect(moved.maxX <= right.frame.maxX + 0.001)
        #expect(moved.maxY <= right.frame.maxY + 0.001)
        #expect(moved.minX >= right.frame.minX - 0.001)
    }

    @Test func detectsMaximizedWindow() {
        // Window covering the left screen minus a 25pt menu bar.
        let maxed = CGRect(x: 0, y: 25, width: 1000, height: 775)
        #expect(ScreenGeometry.fillsScreen(maxed, left))
        let small = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(!ScreenGeometry.fillsScreen(small, left))
    }

    @Test func fillEquivalentPreservesInsets() {
        let maxed = CGRect(x: 0, y: 25, width: 1000, height: 775)   // 25pt top inset
        let moved = ScreenGeometry.fillEquivalent(windowFrame: maxed, from: left, to: right)
        #expect(moved.minX == 1000)
        #expect(moved.minY == 25)             // top inset preserved
        #expect(moved.width == 1000)
        #expect(moved.height == 775)
    }

    @Test func destinationFillsWhenMaximizedElseReposition() {
        let maxed = CGRect(x: 0, y: 25, width: 1000, height: 775)
        let d1 = ScreenGeometry.destinationFrame(windowFrame: maxed, from: left, to: right)
        #expect(d1.width == 1000 && d1.height == 775)   // filled
        let small = CGRect(x: 100, y: 80, width: 300, height: 200)
        let d2 = ScreenGeometry.destinationFrame(windowFrame: small, from: left, to: right)
        #expect(d2.size == small.size)                  // size preserved
    }

    @Test func rightAlignedFullHeightStaysRightAligned() {
        // Flush to the right edge of the left screen, full height, 300 wide.
        let win = CGRect(x: 700, y: 0, width: 300, height: 800)
        let moved = ScreenGeometry.destinationFrame(windowFrame: win, from: left, to: right)
        #expect(moved.maxX == right.frame.maxX)   // still flush right
        #expect(moved.width == 300)               // same width
        #expect(moved.height == 800)              // still full height
    }

    @Test func leftAlignedFullHeightStaysLeftAligned() {
        let win = CGRect(x: 0, y: 0, width: 300, height: 800)
        let moved = ScreenGeometry.destinationFrame(windowFrame: win, from: left, to: right)
        #expect(moved.minX == right.frame.minX)   // flush left of target
        #expect(moved.width == 300)
        #expect(moved.height == 800)
    }

    // Monitor directly ABOVE the mac (Y-down: smaller y). A laptop at y=0..800,
    // external at y=-800..0, same x range.
    private var mac: ScreenInfo { ScreenInfo(id: "mac", frame: CGRect(x: 0, y: 0, width: 1000, height: 800)) }
    private var above: ScreenInfo { ScreenInfo(id: "above", frame: CGRect(x: 0, y: -800, width: 1000, height: 800)) }

    @Test func swipeUpFindsMonitorAbove() {
        let stacked = [mac, above]
        // Swipe up = dy < 0 in Y-down space.
        #expect(ScreenGeometry.targetScreen(forSwipe: CGVector(dx: 0, dy: -200), from: mac, in: stacked)?.id == "above")
    }

    @Test func swipeRightDoesNotFindMonitorAbove() {
        let stacked = [mac, above]
        // Right swipe must NOT move to the monitor that's directly above.
        #expect(ScreenGeometry.targetScreen(forSwipe: CGVector(dx: 200, dy: 0), from: mac, in: stacked) == nil)
    }

    @Test func swipeDownFromAboveReturnsToMac() {
        let stacked = [mac, above]
        #expect(ScreenGeometry.targetScreen(forSwipe: CGVector(dx: 0, dy: 200), from: above, in: stacked)?.id == "mac")
    }

    @Test func sideBySideRightSwipeFindsRight() {
        #expect(ScreenGeometry.targetScreen(forSwipe: CGVector(dx: 200, dy: 0), from: left, in: screens)?.id == "right")
        #expect(ScreenGeometry.targetScreen(forSwipe: CGVector(dx: 0, dy: -200), from: left, in: screens) == nil)
    }

    @Test func swipeOutcomeMovesToAdjacentMonitor() {
        let out = ScreenGeometry.swipeOutcome(swipe: CGVector(dx: 200, dy: 0), from: left, in: screens, snapEnabled: true, minMagnitude: 50)
        #expect(out == .move(screenID: "right"))
    }

    @Test func swipeOutcomeSnapsWhenNoMonitorThatWay() {
        // Single screen: right swipe -> snap right, left -> snap left.
        #expect(ScreenGeometry.swipeOutcome(swipe: CGVector(dx: 200, dy: 0), from: left, in: [left], snapEnabled: true, minMagnitude: 50) == .snap(.right))
        #expect(ScreenGeometry.swipeOutcome(swipe: CGVector(dx: -200, dy: 0), from: right, in: [right], snapEnabled: true, minMagnitude: 50) == .snap(.left))
    }

    @Test func swipeOutcomeNoSnapWhenDisabledOrVertical() {
        #expect(ScreenGeometry.swipeOutcome(swipe: CGVector(dx: 200, dy: 0), from: left, in: [left], snapEnabled: false, minMagnitude: 50) == SwipeOutcomeNone)
        #expect(ScreenGeometry.swipeOutcome(swipe: CGVector(dx: 0, dy: -200), from: left, in: [left], snapEnabled: true, minMagnitude: 50) == SwipeOutcomeNone)
    }

    private var SwipeOutcomeNone: ScreenGeometry.SwipeOutcome { .none }

    @Test func halfRects() {
        let work = CGRect(x: 0, y: 25, width: 1000, height: 775)
        #expect(ScreenGeometry.halfRect(of: work, side: .left) == CGRect(x: 0, y: 25, width: 500, height: 775))
        #expect(ScreenGeometry.halfRect(of: work, side: .right) == CGRect(x: 500, y: 25, width: 500, height: 775))
    }

    // Work area = the left screen minus a 25pt menu bar.
    private var work: CGRect { CGRect(x: 0, y: 25, width: 1000, height: 775) }

    @Test func keyUpFillsThenMovesUp() {
        let small = CGRect(x: 200, y: 200, width: 400, height: 300)
        // Not filling → fill.
        #expect(ScreenGeometry.keyOutcome(arrow: .up, windowFrame: small, work: work, source: mac, screens: [mac, above]) == .fill)
        // Already filling, monitor above → move there.
        let filled = work
        #expect(ScreenGeometry.keyOutcome(arrow: .up, windowFrame: filled, work: work, source: mac, screens: [mac, above]) == .move(screenID: "above"))
        // Already filling, no monitor above → none.
        #expect(ScreenGeometry.keyOutcome(arrow: .up, windowFrame: filled, work: work, source: mac, screens: [mac]) == .none)
    }

    @Test func keyLeftSnapsThenMovesLeft() {
        let small = CGRect(x: 200, y: 200, width: 400, height: 300)
        #expect(ScreenGeometry.keyOutcome(arrow: .left, windowFrame: small, work: work, source: right, screens: screens) == .snap(.left))
        // Already left-aligned (left half), monitor to the left → move.
        let leftHalf = ScreenGeometry.halfRect(of: work, side: .left)
        #expect(ScreenGeometry.keyOutcome(arrow: .left, windowFrame: leftHalf, work: work, source: right, screens: screens) == .move(screenID: "left"))
    }

    @Test func keyDownSmallThenNoMonitorBelow() {
        let small = ScreenGeometry.smallRect(of: work)
        #expect(ScreenGeometry.keyOutcome(arrow: .down, windowFrame: small, work: work, source: mac, screens: [mac, above]) == .none)
        let big = work
        #expect(ScreenGeometry.keyOutcome(arrow: .down, windowFrame: big, work: work, source: mac, screens: [mac]) == .small)
    }

    @Test func adjacentRequiresAxisDominance() {
        // Monitor above-and-slightly-right of mac must count as UP, not RIGHT.
        let aboveRight = ScreenInfo(id: "aboveR", frame: CGRect(x: 150, y: -800, width: 1000, height: 800))
        let set = [mac, aboveRight]
        #expect(ScreenGeometry.adjacentScreen(from: mac, direction: .up, in: set)?.id == "aboveR")
        #expect(ScreenGeometry.adjacentScreen(from: mac, direction: .right, in: set) == nil)
    }

    @Test func titleBarBand() {
        let band = ScreenGeometry.titleBarBand(of: CGRect(x: 10, y: 20, width: 400, height: 300), height: 28)
        #expect(band == CGRect(x: 10, y: 20, width: 400, height: 28))
    }
}
