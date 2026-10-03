import XCTest

@MainActor final class WorkflowTests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  func testPreviewDoesNotRequestHealthAccess() {
    let app = XCUIApplication()
    app.launch()
    #if os(watchOS)
      XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    let preview = app.buttons["preview"]
      for _ in 0..<3 where !preview.isHittable { app.swipeUp() }
      XCTAssertTrue(preview.waitForExistence(timeout: 15), app.debugDescription)
      preview.tap()
      XCTAssertTrue(app.staticTexts["PREVIEW"].waitForExistence(timeout: 10), app.debugDescription)
      XCTAssertTrue(app.staticTexts["142"].exists)
    #else
      app.buttons["Explore sample workout"].tap()
      XCTAssertTrue(
        app.staticTexts["Sample workout · not Health data"].waitForExistence(timeout: 10),
        app.debugDescription)
      XCTAssertTrue(app.staticTexts["Time in zones"].exists)
    #endif
    let capture = XCTAttachment(screenshot: app.screenshot())
    capture.name = "Workout preview"
    capture.lifetime = .keepAlways
    add(capture)
    #if os(watchOS)
      let pause = app.buttons["Pause"]
      for _ in 0..<6 where !pause.isHittable { app.swipeUp() }
      pause.tap()
      XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
      app.buttons["Resume"].tap()
      app.buttons["Close preview"].tap()
      XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 10))
    #else
      app.navigationBars.buttons.firstMatch.tap()
      XCTAssertTrue(app.buttons["Connect to Health"].exists)
    #endif
  }
}
