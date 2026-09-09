import Testing
import UIKit
@testable import Halo_fi_IOS

struct PlaidPresentationTests {
    @Test @MainActor func opensOnlyAfterAppearanceAndOnlyOnce() {
        var opens = 0
        let child = UIViewController()
        let host = LinkHostViewController { attach in
            opens += 1
            attach(child)
        }
        host.loadViewIfNeeded()
        #expect(opens == 0)
        host.viewDidAppear(false)
        #expect(opens == 1)
        #expect(child.parent === host)
        host.viewDidAppear(false) // Returning from bank OAuth must not start another flow.
        #expect(opens == 1)
        host.invalidate()
        #expect(child.parent == nil)
    }

    @Test @MainActor func cancelledPresentationRejectsLateSDKCallback() {
        var attach: ((UIViewController) -> Void)?
        let host = LinkHostViewController { attach = $0 }
        host.loadViewIfNeeded()
        host.viewDidAppear(false)
        host.invalidate()
        let late = UIViewController()
        attach?(late)
        #expect(host.children.isEmpty)
        #expect(late.parent == nil)
    }
}
