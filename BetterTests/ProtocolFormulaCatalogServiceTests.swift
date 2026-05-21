import XCTest
@testable import Better

final class ProtocolFormulaCatalogServiceTests: XCTestCase {
    func testCatalogContainsFixedProtocolVersionsInOrder() {
        XCTAssertEqual(
            ProtocolFormulaCatalog.specs.map(\.label),
            ["V1", "V1.5", "V2", "V3", "V4", "V5"]
        )
    }

    func testCatalogSortUsesFixedOrderInsteadOfShipDateOnly() {
        let now = Date()
        let versions = [
            version(label: "V4", shippedOn: now.addingTimeInterval(-10)),
            version(label: "V1", shippedOn: now),
            version(label: "V1.5", shippedOn: now.addingTimeInterval(-100))
        ]

        XCTAssertEqual(
            ProtocolFormulaCatalog.sorted(versions).map(\.resolvedLabel),
            ["V1", "V1.5", "V4"]
        )
    }

    func testBestVersionExcludesLowDataAndRanksByRestorativePercent() {
        let v1 = version(label: "V1")
        let v2 = version(label: "V2")
        let v3 = version(label: "V3")
        let baseline = ProtocolBaselineSnapshot(
            frozenAt: Date(),
            windowStart: Date().addingTimeInterval(-30 * 86_400),
            windowEnd: Date().addingTimeInterval(-1 * 86_400),
            validNightCount: 14,
            meanRestorativeMin: 120,
            stdRestorativeMin: nil,
            meanRestorativePctOfInBed: 35,
            stdRestorativePctOfInBed: nil,
            meanLongestRestorativeBlockMin: 80,
            stdLongestRestorativeBlockMin: nil,
            continuityCategoryDistribution: [:],
            isInsufficient: false,
            meanDeepMin: 70,
            meanRemMin: 80,
            meanAwakeMin: 30,
            meanLatencyMin: 20
        )

        let lowDataWinner = rollup(versionID: v3.id, nights: 2, restorativePct: 50)
        let modest = rollup(versionID: v1.id, nights: 5, restorativePct: 38)
        let best = rollup(versionID: v2.id, nights: 5, restorativePct: 42)

        let result = ProtocolFormulaCatalogService.bestVersion(
            versions: [v1, v2, v3],
            rollups: [lowDataWinner, modest, best],
            baseline: baseline
        )

        XCTAssertEqual(result?.version.id, v2.id)
        XCTAssertEqual(result?.restorativePctDelta, 7)
    }
}

private extension ProtocolFormulaCatalogServiceTests {
    func version(label: String, shippedOn: Date = Date()) -> ProtocolFormulaVersion {
        ProtocolFormulaVersion(
            id: ProtocolFormulaCatalog.spec(for: label)?.id ?? UUID(),
            displayLabel: label,
            ordinalLabel: label,
            formulaText: "",
            components: [],
            shippedOn: shippedOn,
            colorHex: ProtocolFormulaCatalog.spec(for: label)?.colorHex ?? "#FFFFFF",
            isActive: label == "V5"
        )
    }

    func rollup(versionID: UUID, nights: Int, restorativePct: Double) -> ProtocolVersionRollup {
        ProtocolVersionRollup(
            versionID: versionID,
            nightCount: nights,
            meanRestorativeMin: nil,
            stdRestorativeMin: nil,
            meanRestorativePctOfInBed: restorativePct,
            stdRestorativePctOfInBed: nil,
            meanLongestRestorativeBlockMin: nil,
            stdLongestRestorativeBlockMin: nil,
            continuityDistribution: [:],
            meanDeepMin: 80,
            stdDeepMin: nil,
            meanRemMin: 90,
            stdRemMin: nil,
            meanAwakeMin: 20,
            stdAwakeMin: nil,
            meanTotalSleepMin: nil,
            stdTotalSleepMin: nil,
            meanLatencyMin: 12,
            stdLatencyMin: nil,
            meanSleepScore: nil,
            stdSleepScore: nil
        )
    }
}
