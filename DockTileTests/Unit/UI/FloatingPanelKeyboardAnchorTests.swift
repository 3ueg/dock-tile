import CoreGraphics
import Testing
@testable import Dock_Tile

/// Issue #15: a ⌘Tab activation has no click, so anchoring at the mouse put the popover wherever
/// the pointer happened to be along the Dock. Failing values: the mouse (or any point other than
/// the remembered click) used when a click is known; a remembered click on a display that is no
/// longer connected trusted; no click known and anything but the Dock screen's centre returned.
struct FloatingPanelKeyboardAnchorTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

    @Test("The tile's last Dock click is used when it is on a connected screen")
    func usesLastClick() {
        let click = CGPoint(x: 809, y: 40)
        #expect(FloatingPanel.keyboardAnchorPoint(lastClick: click, screens: [builtIn, external],
                                                  dockScreen: builtIn) == click)
    }

    @Test("A click remembered on an external screen is still used while it is connected")
    func usesClickOnOtherScreen() {
        let click = CGPoint(x: 2600, y: 30)
        #expect(FloatingPanel.keyboardAnchorPoint(lastClick: click, screens: [builtIn, external],
                                                  dockScreen: builtIn) == click)
    }

    @Test("No click yet → the centre of the Dock's screen")
    func centreWithoutClick() {
        #expect(FloatingPanel.keyboardAnchorPoint(lastClick: nil, screens: [builtIn],
                                                  dockScreen: builtIn) == CGPoint(x: 756, y: 491))
    }

    @Test("A click on a display that was unplugged → the centre of the Dock's screen")
    func centreWhenClickScreenGone() {
        let click = CGPoint(x: 2600, y: 30)   // was on `external`
        #expect(FloatingPanel.keyboardAnchorPoint(lastClick: click, screens: [builtIn],
                                                  dockScreen: builtIn) == CGPoint(x: 756, y: 491))
    }
}
