import XCTest

@testable import Leader_Key

/// The trigger key after the HID remap. Any other keycode stands in for a
/// normal key being chorded with it.
private let triggerUp: CGKeyCode = 0x4F  // F18
private let keyJ: CGKeyCode = 0x26
private let keyK: CGKeyCode = 0x28

final class TriggerGestureTests: XCTestCase {

  private func gesture(
    tap: TapBehavior = .leaderKey,
    hold: HoldBehavior = .hyperOnly,
    tapTimeout: TimeInterval = 0.25,
    holdThreshold: TimeInterval = 0.15,
    closePeekOnRelease: Bool = true
  ) -> TriggerGesture {
    TriggerGesture(
      config: .init(
        tapBehavior: tap,
        holdBehavior: hold,
        tapTimeout: tapTimeout,
        holdThreshold: holdThreshold,
        closePeekOnRelease: closePeekOnRelease))
  }

  // MARK: - Tap

  // A quick press and release with nothing else pressed is a tap.
  func testQuickReleaseIsATap() {
    var g = gesture(tap: .leaderKey)
    XCTAssertEqual(g.triggerDown(at: 0), [])
    XCTAssertEqual(g.triggerUp(at: 0.05), [.cancelHoldTimer, .tap(.leaderKey)])
    XCTAssertEqual(g.phase, .idle)
  }

  // Releasing later than the timeout is a hold that did nothing. Firing the
  // tap action here is what makes Escape show up at random.
  func testSlowReleaseIsNotATap() {
    var g = gesture(tapTimeout: 0.25)
    g.triggerDown(at: 0)
    XCTAssertEqual(g.triggerUp(at: 0.3), [.cancelHoldTimer])
  }

  // The boundary belongs to the hold, not the tap.
  func testReleaseExactlyAtTimeoutIsNotATap() {
    var g = gesture(tapTimeout: 0.25)
    g.triggerDown(at: 0)
    XCTAssertEqual(g.triggerUp(at: 0.25), [.cancelHoldTimer])
  }

  // Whatever the tap is configured to do is what comes back.
  func testTapBehaviourIsReported() {
    for behavior in TapBehavior.allCases {
      var g = gesture(tap: behavior)
      g.triggerDown(at: 0)
      XCTAssertEqual(
        g.triggerUp(at: 0.05), [.cancelHoldTimer, .tap(behavior)],
        "tap behaviour \(behavior) should be handed back verbatim")
    }
  }

  // MARK: - Chord

  // A key arriving while the trigger is down makes it a Hyper chord.
  func testKeyWhileHeldBecomesHyper() {
    var g = gesture()
    g.triggerDown(at: 0)

    let (disposition, effects) = g.otherKeyDown(keyJ)
    XCTAssertEqual(disposition, .passWithHyper)
    XCTAssertEqual(effects, [.cancelHoldTimer])
    XCTAssertEqual(g.phase, .hyper)
  }

  // Once a chord has claimed the press, releasing the trigger is silent.
  func testChordSuppressesTheTapAction() {
    var g = gesture(tap: .escape)
    g.triggerDown(at: 0)
    g.otherKeyDown(keyJ)

    // Well inside the tap timeout, and still no tap.
    XCTAssertEqual(g.triggerUp(at: 0.05), [.cancelHoldTimer])
  }

  // Every further key in the same chord gets the flags too.
  func testSecondKeyInChordAlsoGetsHyper() {
    var g = gesture()
    g.triggerDown(at: 0)
    g.otherKeyDown(keyJ)

    let (disposition, effects) = g.otherKeyDown(keyK)
    XCTAssertEqual(disposition, .passWithHyper)
    XCTAssertEqual(effects, [], "the hold timer is already cancelled")
  }

  // Keys pressed with the trigger up are none of our business.
  func testKeyWithoutTriggerPassesThrough() {
    var g = gesture()
    let (disposition, effects) = g.otherKeyDown(keyJ)
    XCTAssertEqual(disposition, .pass)
    XCTAssertEqual(effects, [])
  }

  // MARK: - Key-up flag pairing
  //
  // Caps Lock is normally released before the key it was chorded with. A
  // key-up matched against the current phase instead of its own key-down
  // arrives bare, and an app pairing the two by modifier state then thinks
  // the chord is still held.

  func testKeyUpKeepsHyperAfterTriggerIsReleasedFirst() {
    var g = gesture()
    g.triggerDown(at: 0)
    g.otherKeyDown(keyJ)
    g.triggerUp(at: 0.1)

    XCTAssertEqual(
      g.otherKeyUp(keyJ), .passWithHyper,
      "J went down carrying Hyper, so its key-up has to carry it as well")
  }

  func testKeyUpIsBareWhenItsKeyDownWasBare() {
    var g = gesture()
    XCTAssertEqual(g.otherKeyUp(keyJ), .pass)
  }

  // The latch is per key, not global.
  func testOnlyTheChordedKeyKeepsHyperOnRelease() {
    var g = gesture()
    g.triggerDown(at: 0)
    g.otherKeyDown(keyJ)
    g.triggerUp(at: 0.1)

    XCTAssertEqual(g.otherKeyUp(keyK), .pass, "K was never chorded")
    XCTAssertEqual(g.otherKeyUp(keyJ), .passWithHyper)
  }

  // Each key-up consumes its own latch, so a repeat does not get flags.
  func testLatchIsConsumedOnce() {
    var g = gesture()
    g.triggerDown(at: 0)
    g.otherKeyDown(keyJ)
    XCTAssertEqual(g.otherKeyUp(keyJ), .passWithHyper)
    XCTAssertEqual(g.otherKeyUp(keyJ), .pass)
  }

  // MARK: - Hold

  // Hyper-only mode never arms a timer, so a lone hold does nothing at all.
  func testHyperOnlyModeStartsNoTimer() {
    var g = gesture(hold: .hyperOnly)
    XCTAssertEqual(g.triggerDown(at: 0), [])
    XCTAssertEqual(g.holdThresholdReached(), [], "nothing should have armed")
  }

  func testPeekModeArmsTheTimer() {
    var g = gesture(hold: .peekLeaderKey, holdThreshold: 0.15)
    XCTAssertEqual(g.triggerDown(at: 0), [.startHoldTimer(after: 0.15)])
  }

  func testHoldOpensThePanel() {
    var g = gesture(hold: .peekLeaderKey)
    g.triggerDown(at: 0)
    XCTAssertEqual(g.holdThresholdReached(), [.openPanel])
    XCTAssertEqual(g.phase, .peek)
  }

  // Releasing after a peek closes the panel and does not also fire the tap.
  func testReleaseAfterPeekDismissesThePanel() {
    var g = gesture(tap: .escape, hold: .peekLeaderKey)
    g.triggerDown(at: 0)
    g.holdThresholdReached()
    XCTAssertEqual(g.triggerUp(at: 0.2), [.cancelHoldTimer, .dismissPanel])
  }

  func testReleaseAfterPeekCanLeaveThePanelUp() {
    var g = gesture(hold: .peekLeaderKey, closePeekOnRelease: false)
    g.triggerDown(at: 0)
    g.holdThresholdReached()
    XCTAssertEqual(g.triggerUp(at: 0.2), [.cancelHoldTimer])
  }

  // While the panel is peeking it is key window, so keys go to AppKit rather
  // than getting Hyper merged in.
  func testKeysDuringPeekPassThroughUntouched() {
    var g = gesture(hold: .peekLeaderKey)
    g.triggerDown(at: 0)
    g.holdThresholdReached()

    let (disposition, effects) = g.otherKeyDown(keyJ)
    XCTAssertEqual(disposition, .pass)
    XCTAssertEqual(effects, [])
  }

  // A key landing before the threshold wins the race, and the timer that
  // fires afterwards must not reopen the panel.
  func testKeyBeatingTheTimerBlocksThePeek() {
    var g = gesture(hold: .peekLeaderKey)
    g.triggerDown(at: 0)
    g.otherKeyDown(keyJ)

    XCTAssertEqual(g.phase, .hyper)
    XCTAssertEqual(g.holdThresholdReached(), [], "the chord already claimed it")
    XCTAssertEqual(g.phase, .hyper)
  }

  // Same race the other way: released before the timer fired.
  func testTimerAfterReleaseDoesNothing() {
    var g = gesture(hold: .peekLeaderKey)
    g.triggerDown(at: 0)
    g.triggerUp(at: 0.05)

    XCTAssertEqual(g.holdThresholdReached(), [])
    XCTAssertEqual(g.phase, .idle)
  }

  // MARK: - Key repeat

  // A function key repeats while held. Rearming on each repeat would restart
  // the hold timer forever and the peek would never fire.
  func testTriggerRepeatDoesNotRearmTheHoldTimer() {
    var g = gesture(hold: .peekLeaderKey, holdThreshold: 0.15)
    XCTAssertEqual(g.triggerDown(at: 0), [.startHoldTimer(after: 0.15)])
    XCTAssertEqual(g.triggerDown(at: 0.05), [], "a repeat must not rearm")
    XCTAssertEqual(g.triggerDown(at: 0.1), [])
  }

  // The tap window runs from the original press. Measured from the last
  // repeat instead, this 200ms hold would look like 100ms and fire a tap.
  // Hyper-only mode, so no timer is involved in the outcome.
  func testTriggerRepeatDoesNotRestartTheTapWindow() {
    var g = gesture(tap: .escape, hold: .hyperOnly, tapTimeout: 0.15)
    g.triggerDown(at: 0)
    g.triggerDown(at: 0.05)
    g.triggerDown(at: 0.1)
    XCTAssertEqual(g.triggerUp(at: 0.2), [.cancelHoldTimer])
  }

  // The mode can change while a hold timer is already in flight, and a timer
  // handler that has started cannot be called back. The gesture has to refuse
  // the peek on its own rather than trust the caller.
  func testModeSwitchedToHyperOnlyMidPressRefusesThePeek() {
    var g = gesture(hold: .peekLeaderKey)
    g.triggerDown(at: 0)

    g.config.holdBehavior = .hyperOnly

    XCTAssertEqual(g.holdThresholdReached(), [])
    XCTAssertEqual(g.phase, .armed, "still just a held key, not a peek")
  }

  // MARK: - Reset

  // After wake, or after the system disables the tap, a key-up may have been
  // eaten. Reset has to leave nothing behind.
  func testResetClearsAHalfFinishedGesture() {
    var g = gesture()
    g.triggerDown(at: 0)
    g.otherKeyDown(keyJ)

    g.reset()

    XCTAssertEqual(g.phase, .idle)
    XCTAssertEqual(g.otherKeyUp(keyJ), .pass, "the latch should be gone")
    XCTAssertEqual(g.triggerUp(at: 0.05), [.cancelHoldTimer])
  }
}
