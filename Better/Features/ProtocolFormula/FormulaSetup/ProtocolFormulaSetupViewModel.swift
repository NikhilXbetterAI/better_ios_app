import Foundation
import SwiftUI

@MainActor
@Observable
final class ProtocolFormulaSetupViewModel {
    var versions: [ProtocolFormulaVersion] = []
    /// Per-version lock state — `true` when at least one ProtocolNightLog references it.
    var isLocked: [UUID: Bool] = [:]
    var editing: ProtocolFormulaVersion?
    var errorMessage: String?

    private let localRepository: LocalDataRepositoryProtocol
    private let catalogService: ProtocolFormulaCatalogService

    init(localRepository: LocalDataRepositoryProtocol) {
        self.localRepository = localRepository
        self.catalogService = ProtocolFormulaCatalogService(repository: localRepository)
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        do {
            versions = try await catalogService.ensureCatalogVersions()
            var locks: [UUID: Bool] = [:]
            for v in versions {
                let hasLogs = try await localRepository.hasNightLogs(forVersionID: v.id)
                let placeholderAwaitingBackfill = v.isImportedPlaceholder && v.formulaText.isEmpty
                locks[v.id] = hasLogs && !placeholderAwaitingBackfill
            }
            isLocked = locks
        } catch {
            errorMessage = "Couldn't load versions: \(error.localizedDescription)"
        }
    }

    func beginEditing(_ version: ProtocolFormulaVersion) {
        editing = version
    }

    func beginNew() {
        let nextIndex = versions.count % ProtocolFormulaVersion.defaultPaletteHexes.count
        editing = ProtocolFormulaVersion(
            displayLabel: "V\(versions.count + 1)",
            ordinalLabel: "V\(versions.count + 1)",
            formulaText: "",
            components: [],
            shippedOn: Date(),
            colorHex: ProtocolFormulaVersion.defaultPaletteHexes[nextIndex],
            isActive: versions.isEmpty
        )
    }

    func makeNewVersionFrom(_ source: ProtocolFormulaVersion) {
        let nextIndex = versions.count % ProtocolFormulaVersion.defaultPaletteHexes.count
        editing = ProtocolFormulaVersion(
            displayLabel: "V\(versions.count + 1)",
            ordinalLabel: "V\(versions.count + 1)",
            formulaText: source.formulaText,
            components: source.components,
            shippedOn: Date(),
            colorHex: ProtocolFormulaVersion.defaultPaletteHexes[nextIndex],
            isActive: true
        )
    }

    func cancelEditing() { editing = nil }

    func save(_ draft: ProtocolFormulaVersion) async {
        do {
            try await localRepository.saveFormulaVersion(draft)
            editing = nil
            await reload()
        } catch ProtocolFormulaRepositoryError.formulaTextLocked {
            errorMessage = "This version is locked — create a new version instead."
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    /// Marks `version` as the active formula. The repository's active-singleton
    /// enforcement automatically clears `isActive` on every other row.
    func setActive(_ version: ProtocolFormulaVersion) async {
        var updated = version
        updated.isActive = true
        do {
            try await localRepository.saveFormulaVersion(updated)
            await reload()
        } catch {
            errorMessage = "Couldn't set as current: \(error.localizedDescription)"
        }
    }

    func archive(_ version: ProtocolFormulaVersion) async {
        do {
            try await catalogService.archiveVersion(id: version.id)
            await reload()
        } catch {
            errorMessage = "Couldn't archive: \(error.localizedDescription)"
        }
    }
}
