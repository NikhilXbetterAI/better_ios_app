import SwiftUI

struct PrivacyControlsView: View {
    @Bindable var service: PrivacyDataService
    let healthAuthState: HealthAuthorizationPresentationState
    let onResync: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showPrivacyPolicy = false

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            sectionHeader

            if service.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BetterSpacing.medium)
            } else {
                if let inventory = service.inventory {
                    dataInventoryView(inventory)
                }
                if let error = service.errorMessage {
                    Text(error)
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.danger)
                }
                privacyPolicyButton
                actionButtons
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task { await service.loadInventory() }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .alert("Delete all health data?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await service.deleteAllLocalData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all sleep sessions, baselines, protocol check-ins, context check-ins, and onboarding answers stored on this device. Apple Health data is not affected. The app will return to onboarding.")
        }
    }

    // MARK: - Sub-views

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Privacy & Data")
                .font(BetterTypography.subheadline)
                .foregroundStyle(BetterColors.text)
            Text("All data stays on this device. Nothing is sent to external servers.")
                .font(BetterTypography.caption)
                .foregroundStyle(BetterColors.subtext)
        }
    }

    private func dataInventoryView(_ inventory: LocalDataInventory) -> some View {
        VStack(spacing: 0) {
            inventoryRow(
                label: "Sleep sessions",
                value: "\(inventory.sleepSessionCount)",
                detail: dateRangeText(inventory)
            )
            Divider().padding(.leading, BetterSpacing.large)
            inventoryRow(label: "Rolling baseline records", value: "\(inventory.baselineCount)")
            Divider().padding(.leading, BetterSpacing.large)
            inventoryRow(
                label: "Protocol baseline",
                value: protocolBaselineValue(inventory),
                detail: protocolBaselineDetail(inventory)
            )
            Divider().padding(.leading, BetterSpacing.large)
            inventoryRow(label: "Protocol check-ins", value: "\(inventory.protocolAdherenceCount)")
            Divider().padding(.leading, BetterSpacing.large)
            inventoryRow(label: "Context check-ins", value: "\(inventory.contextEntryCount)", detail: lastContextDateText(inventory))
            Divider().padding(.leading, BetterSpacing.large)
            inventoryRow(label: "Alerts", value: "\(inventory.alertCount)")
            Divider().padding(.leading, BetterSpacing.large)
            inventoryRow(label: "Manual biology entries", value: "\(inventory.manualBiologyEntryCount)")
        }
        .background(BetterColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func inventoryRow(label: String, value: String, detail: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(BetterTypography.footnote)
                    .foregroundStyle(BetterColors.text)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }
            Spacer()
            Text(value)
                .font(BetterTypography.caption.monospacedDigit())
                .foregroundStyle(BetterColors.subtext)
        }
        .padding(.horizontal, BetterSpacing.medium)
        .padding(.vertical, 10)
    }

    private var actionButtons: some View {
        VStack(spacing: BetterSpacing.small) {
            healthKitStatusRow
            Divider()
            resyncButton
            Divider()
            deleteButton
        }
    }

    private var privacyPolicyButton: some View {
        Button { showPrivacyPolicy = true } label: {
            Label("Privacy Policy", systemImage: "lock.shield")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.brand)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    private var healthKitStatusRow: some View {
        HStack {
            Image(systemName: healthStatusIcon)
                .foregroundStyle(healthStatusColor)
                .frame(width: 22)
            Text("Apple Health")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.text)
            Spacer()
            Text(healthStatusLabel)
                .font(BetterTypography.caption)
                .foregroundStyle(healthStatusColor)
        }
        .padding(.vertical, 6)
    }

    private var resyncButton: some View {
        Button {
            onResync()
        } label: {
            Label("Re-sync from Apple Health", systemImage: "arrow.clockwise.heart")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.brand)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .disabled(service.isLoading)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete all local health data", systemImage: "trash")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .disabled(service.isLoading)
    }

    // MARK: - Helpers

    private var healthStatusLabel: String {
        switch healthAuthState {
        case .canQueryHealthData: "Connected"
        case .notRequested: "Not connected"
        case .healthDataUnavailable: "Unavailable"
        case .noReadableSleepData: "No sleep data"
        case .requestCompleted: "Pending"
        case .failed: "Error"
        }
    }

    private var healthStatusIcon: String {
        switch healthAuthState {
        case .canQueryHealthData: "checkmark.circle.fill"
        case .notRequested, .requestCompleted: "circle"
        case .healthDataUnavailable, .failed: "exclamationmark.circle.fill"
        case .noReadableSleepData: "moon.zzz.fill"
        }
    }

    private var healthStatusColor: Color {
        switch healthAuthState {
        case .canQueryHealthData: BetterColors.success
        case .notRequested, .requestCompleted: BetterColors.subtext
        case .healthDataUnavailable, .failed: BetterColors.warning
        case .noReadableSleepData: BetterColors.brand
        }
    }

    private func dateRangeText(_ inventory: LocalDataInventory) -> String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        guard let oldest = inventory.oldestSessionDate else { return nil }
        let newestText = inventory.newestSessionDate.map { formatter.string(from: $0) } ?? "—"
        return "\(formatter.string(from: oldest)) – \(newestText)"
    }

    private func lastContextDateText(_ inventory: LocalDataInventory) -> String? {
        guard let date = inventory.lastContextEntryDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Last: \(formatter.string(from: date))"
    }

    private func protocolBaselineValue(_ inventory: LocalDataInventory) -> String {
        guard inventory.protocolBaselineSnapshotCount > 0 else { return "Not created" }
        guard let count = inventory.protocolBaselineValidNightCount else { return "Created" }
        return "\(count) night\(count == 1 ? "" : "s")"
    }

    private func protocolBaselineDetail(_ inventory: LocalDataInventory) -> String? {
        guard inventory.protocolBaselineSnapshotCount > 0 else { return "Builds after enough qualifying pre-protocol sleep nights." }
        if inventory.protocolBaselineIsInsufficient == true {
            return "Building — needs \(ProtocolBaselineService.minimumPersistedNightCount) qualifying nights."
        }
        return "Frozen comparator for Protocol Formula."
    }
}

#if DEBUG
#Preview("Privacy Controls") {
    let env = AppEnvironment.preview()
    ScrollView {
        PrivacyControlsView(
            service: env.privacyDataService,
            healthAuthState: .canQueryHealthData,
            onResync: {}
        )
        .padding()
    }
    .background(BetterColors.background)
}
#endif
