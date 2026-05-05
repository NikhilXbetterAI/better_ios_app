import Foundation

nonisolated enum ProtocolCatalog {
    static func load(bundle: Bundle = .main) -> [ProtocolItem] {
        guard let url = bundle.url(forResource: "protocols", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ProtocolItem].self, from: data)
        else {
            return fallback
        }

        return decoded.sorted { $0.sortOrder < $1.sortOrder }
    }

    static let fallback: [ProtocolItem] = [
        ProtocolItem(
            id: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000001")!,
            name: "Magnesium Glycinate",
            dose: "400 mg",
            benefit: "Supports relaxation and deep sleep consistency",
            instructions: "Take 30-60 min before bed with water.",
            isActive: true,
            sortOrder: 0,
            colorHex: "#5E5CE6"
        ),
        ProtocolItem(
            id: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000002")!,
            name: "Melatonin",
            dose: "0.5 mg",
            benefit: "Supports sleep onset timing",
            instructions: "Take 1-2 hrs before target bedtime.",
            isActive: true,
            sortOrder: 1,
            colorHex: "#64D2FF"
        ),
        ProtocolItem(
            id: UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000003")!,
            name: "L-Theanine",
            dose: "200 mg",
            benefit: "Supports a calmer wind-down routine",
            instructions: "Take with the evening protocol or caffeine-free tea.",
            isActive: true,
            sortOrder: 2,
            colorHex: "#32D74B"
        )
    ]
}
