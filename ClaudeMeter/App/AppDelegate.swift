import AppKit

/// App delegate to manage menu bar lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appModel: AppModel?
    private var menuBarManager: MenuBarManager?

    #if DEBUG
    private var isDemoMode: Bool = false
    #endif

    func configure(appModel: AppModel) {
        self.appModel = appModel
    }

    #if DEBUG
    func configureDemoMode(_ enabled: Bool) {
        isDemoMode = enabled
    }
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        SessionKeyImportPromptCoordinator.install()

        guard let appModel else {
            let fallbackModel = AppModel()
            self.appModel = fallbackModel
            startMenuBar(with: fallbackModel)
            return
        }
        startMenuBar(with: appModel)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func startMenuBar(with appModel: AppModel) {
        let manager = MenuBarManager(appModel: appModel)
        menuBarManager = manager

        #if DEBUG
        // Skip bootstrap when the app is launched as a test host, so test runs
        // never touch the real keychain (which triggers password prompts when
        // the build is unsigned)
        if isDemoMode || Self.isRunningTests {
            manager.startWithoutBootstrap()
        } else {
            manager.start()
        }
        #else
        manager.start()
        #endif
    }

    #if DEBUG
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    #endif
}
