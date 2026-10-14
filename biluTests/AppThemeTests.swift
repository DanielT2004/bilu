import UIKit
import XCTest
@testable import bilu

final class AppThemeTests: XCTestCase {
    func testBundledFontsLoadByPostScriptName() {
        for name in AppTheme.FontName.all {
            XCTAssertNotNil(UIFont(name: name, size: 17), "\(name) is not registered (check Info.plist UIAppFonts)")
        }
    }

    func testFontLicensesAreBundled() {
        for file in ["NotoSerif-OFL", "PlusJakartaSans-OFL"] {
            XCTAssertNotNil(Bundle.main.url(forResource: file, withExtension: "txt"), "\(file).txt missing from the app bundle")
        }
    }

    func testIconTokensAreDistinctValidSymbols() {
        let icons = [AppTheme.Icon.saved, AppTheme.Icon.savedFilled,
                     AppTheme.Icon.wantToGo, AppTheme.Icon.wantToGoFilled,
                     AppTheme.Icon.vibe]
        XCTAssertEqual(Set(icons).count, icons.count)
        for icon in icons {
            XCTAssertNotNil(UIImage(systemName: icon), "\(icon) is not an SF Symbol")
        }
    }
}
