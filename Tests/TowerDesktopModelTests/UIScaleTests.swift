import XCTest
import Foundation
@testable import TowerDesktopModel

final class UIScaleTests:XCTestCase {
    func testReadableDefaultsRespectWindowsDPIAnd4KWindows() {
        let ui=DesktopUIScale()
        XCTAssertEqual(ui.factor(width:1440,height:940,contentScale:1),1.25)
        XCTAssertEqual(ui.factor(width:2160,height:1410,contentScale:1.5),1.5)
        XCTAssertEqual(ui.factor(width:3840,height:2054,contentScale:1.5),2)
    }
    func testExplicitPreferencePersistsAndKeepsControlsInsideSmallWindows() throws {
        let ui=try JSONDecoder().decode(DesktopUIScale.self,from:JSONEncoder().encode(DesktopUIScale(requested:2)))
        XCTAssertEqual(ui.requested,2)
        XCTAssertEqual(ui.factor(width:3840,height:2054,contentScale:1),2)
        XCTAssertEqual(ui.factor(width:1440,height:940,contentScale:1.5),1.25)
        XCTAssertEqual(ui.factor(width:1080,height:650,contentScale:2),1)
        XCTAssertEqual(ui.factor(width:.nan,height:940,contentScale:2),1)
        var cycle=ui;cycle.cycle();XCTAssertEqual(cycle.requested,0)
    }
}
