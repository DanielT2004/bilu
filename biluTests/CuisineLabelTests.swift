import XCTest
@testable import bilu

final class CuisineLabelTests: XCTestCase {
    func testInfersFromNameDishAndTags() {
        XCTAssertEqual(CuisineLabel.infer(name: "Teddy's Red Tacos"), "Mexican")
        XCTAssertEqual(CuisineLabel.infer(name: "Sonoratown", dish: "Carne asada burrito"), "Mexican")
        XCTAssertEqual(CuisineLabel.infer(name: "Tsujita LA Artisan Noodle", dish: "Tsukemen ramen"), "Japanese")
        XCTAssertEqual(CuisineLabel.infer(name: "Bestia", explanation: "Rustic Italian with house pasta"), "Italian")
        XCTAssertEqual(CuisineLabel.infer(name: "Spot", tags: ["Asian noodles & broth", "Pho"]), "Vietnamese")
        XCTAssertEqual(CuisineLabel.infer(name: "Tartine", dish: "Morning bun", explanation: "Bakery"), "Café & Bakery")
    }

    func testExplicitCuisineTagWins() {
        XCTAssertEqual(CuisineLabel.infer(name: "Taco Palace", tags: ["korean"]), "Korean")
    }

    func testAvoidsWordFragmentsAndReturnsNilWhenUnsure() {
        XCTAssertNil(CuisineLabel.infer(name: "Phone Repair"))
        XCTAssertNil(CuisineLabel.infer(name: "Baobab Tree"))
        XCTAssertNil(CuisineLabel.infer(name: "Grand Central Market"))
        XCTAssertNil(CuisineLabel.infer())
    }

    func testPluralsAndSuffixesMatch() {
        XCTAssertEqual(CuisineLabel.infer(dish: "Pork dumplings"), "Chinese")
        XCTAssertEqual(CuisineLabel.infer(name: "La Taqueria"), "Mexican")
        XCTAssertEqual(CuisineLabel.infer(name: "Pizzeria Mozza"), "Italian")
    }
}
