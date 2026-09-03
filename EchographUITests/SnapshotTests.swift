import XCTest

/// Drives the running app through key screens and saves screenshots to
/// /tmp/echograph-snapshots/ where the host script can pick them up.
final class SnapshotTests: XCTestCase {

    // Stable IDs match the ones we seed in UITestHooks.seedMockRecordings()
    private let firstRecordingID = "AAAAAAAA-1111-1111-1111-111111111111"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func snapshot(_ name: String) {
        let img = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(image: img.image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = "/tmp/echograph-snapshots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? img.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    private func launchedApp(forcePaywall: Bool = false, exhaustFreeTranscriptions: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest_seed_recordings"]
        if forcePaywall { app.launchArguments += ["-uitest_force_paywall"] }
        if exhaustFreeTranscriptions { app.launchArguments += ["-uitest_exhaust_free_transcriptions"] }
        app.launch()
        sleep(2)
        return app
    }

    private func tapFirstRecording(_ app: XCUIApplication) {
        // Coordinate-based tap is the only reliable way to hit a SwiftUI List
        // NavigationLink row from XCUITest in iOS 17+.
        let window = app.windows.firstMatch
        let coord = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        coord.tap()
    }

    /// Taps the second seeded recording ("Лекция…") — unlike the first one,
    /// it has no preset transcript, so it lands on the "No transcript yet" /
    /// Transcribe-menu screen instead of an already-transcribed detail view.
    private func tapSecondRecording(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        let coord = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        coord.tap()
    }

    // MARK: - Tests

    func test_01_home() {
        _ = launchedApp()
        snapshot("01-home")
    }

    func test_02_recording_detail() {
        let app = launchedApp()
        tapFirstRecording(app)
        sleep(2)
        snapshot("02-recording-detail")
    }

    func test_03_settings() {
        let app = launchedApp()
        let gear = app.buttons["settingsButton"].firstMatch
        if gear.waitForExistence(timeout: 3) {
            gear.tap()
        }
        sleep(2)
        snapshot("03-settings")
    }

    func test_04_paywall() {
        // Parakeet itself is free (up to the free-transcription quota) —
        // the paywall now shows only once that quota is exhausted, not
        // merely for lacking a subscription. Exhaust it deterministically
        // instead of actually running 10 (network-downloading) transcriptions.
        let app = launchedApp(forcePaywall: true, exhaustFreeTranscriptions: true)
        tapSecondRecording(app)
        sleep(2)

        let transcribe = app.buttons["transcribeMenu"].firstMatch
        XCTAssertTrue(transcribe.waitForExistence(timeout: 5), "Transcribe menu not found")
        transcribe.tap()
        sleep(1)

        // Tap Parakeet v3 inside the menu (free quota exhausted → opens paywall).
        let parakeetOption = app.buttons["parakeetOption"].firstMatch
        XCTAssertTrue(parakeetOption.waitForExistence(timeout: 3), "Parakeet v3 option not found")
        parakeetOption.tap()
        sleep(2)

        snapshot("04-paywall")
    }

    func test_05_summary_card() {
        let app = launchedApp()
        tapFirstRecording(app)
        sleep(2)
        // Scroll down to bring summary section into view.
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
            sleep(1)
        }
        snapshot("05-summary-card")
    }

    func test_06_search() {
        let app = launchedApp()
        // With placement: .navigationBarDrawer(displayMode: .always) the
        // search field is rendered in the navigation bar from launch.
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        searchField.tap()
        searchField.typeText("research")
        sleep(2)
        snapshot("06-search")
    }
}
