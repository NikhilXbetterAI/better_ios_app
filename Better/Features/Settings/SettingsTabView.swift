import SwiftUI
import UIKit

struct SettingsTabView: View {
    @Bindable var viewModel: SettingsViewModel
    @Bindable var sleepModeViewModel: SleepModeViewModel
    @Bindable var redLightFilterService: RedLightFilterService
    @Bindable var alertsViewModel: AlertsViewModel
    
    @State private var showPrivacyPolicy = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    header
                    
                    profileCardSummarySection
                    
                    // SECTION 1: PROFILE & GOAL
                    settingsGroupHeader(title: "Profile & Sleep Goal")
                    settingsGroupCard {
                        NavigationLink {
                            ProfileSettingsDetailView(viewModel: viewModel)
                        } label: {
                            settingsRow(
                                title: "Profile Settings",
                                subtitle: "Name, sleep goal, baseline window",
                                systemImage: "person.crop.circle.fill",
                                iconColor: BetterColors.brandLight
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // SECTION 2: PREFERENCES
                    settingsGroupHeader(title: "Preferences")
                    settingsGroupCard {
                        NavigationLink {
                            AlertsTabView(viewModel: alertsViewModel)
                        } label: {
                            settingsRow(
                                title: "Alerts & Notifications",
                                subtitle: "Configure reminders and smart alerts",
                                systemImage: "bell.fill",
                                iconColor: BetterColors.warning
                            )
                        }
                        .buttonStyle(.plain)
                        
                        Divider().background(Color.white.opacity(0.06))
                        
                        NavigationLink {
                            SleepModeDetailView(sleepModeViewModel: sleepModeViewModel)
                        } label: {
                            settingsRow(
                                title: "Sleep Mode Schedule",
                                subtitle: "Automate Do Not Disturb & sleep windows",
                                systemImage: "moon.zzz.fill",
                                iconColor: BetterColors.stageDeep
                            )
                        }
                        .buttonStyle(.plain)
                        
                        Divider().background(Color.white.opacity(0.06))
                        
                        NavigationLink {
                            RedLightDetailView(service: redLightFilterService)
                        } label: {
                            settingsRow(
                                title: "Screen Red Light Filter",
                                subtitle: "Dim display blue light at bedtime",
                                systemImage: "eye.fill",
                                iconColor: BetterColors.stageAwake
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // SECTION 3: INTEGRATIONS
                    settingsGroupHeader(title: "Integrations & Sync")
                    settingsGroupCard {
                        appleHealthRow
                        
                        Divider().background(Color.white.opacity(0.06))
                        
                        NavigationLink {
                            ConnectedDevicesDetailView(sources: viewModel.connectedSources)
                        } label: {
                            settingsRow(
                                title: "Connected Devices",
                                subtitle: "\(viewModel.connectedSources.count) source\(viewModel.connectedSources.count == 1 ? "" : "s") identified",
                                systemImage: "applewatch",
                                iconColor: BetterColors.cyan
                            )
                        }
                        .buttonStyle(.plain)
                        
                        Divider().background(Color.white.opacity(0.06))
                        
                        Button {
                            Task {
                                await viewModel.triggerSync()
                            }
                        } label: {
                            settingsActionRow(
                                title: "Re-sync from Apple Health",
                                systemImage: "arrow.clockwise.heart",
                                iconColor: BetterColors.success
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // SECTION 4: DATA & PRIVACY
                    settingsGroupHeader(title: "Data & Privacy")
                    settingsGroupCard {
                        NavigationLink {
                            ResearchExportDetailView(viewModel: viewModel)
                        } label: {
                            settingsRow(
                                title: "Research CSV Export",
                                subtitle: "Export zipped metrics and insights",
                                systemImage: "square.and.arrow.up.fill",
                                iconColor: BetterColors.violet
                            )
                        }
                        .buttonStyle(.plain)
                        
                        Divider().background(Color.white.opacity(0.06))
                        
                        NavigationLink {
                            DiagnosticsDetailView(viewModel: viewModel, privacyService: viewModel.privacyService)
                        } label: {
                            settingsRow(
                                title: "Database & Diagnostics",
                                subtitle: "Data inventory, diagnostic runs, resets",
                                systemImage: "stethoscope",
                                iconColor: BetterColors.hrv
                            )
                        }
                        .buttonStyle(.plain)
                        
                        Divider().background(Color.white.opacity(0.06))
                        
                        Button {
                            showPrivacyPolicy = true
                        } label: {
                            settingsActionRow(
                                title: "Privacy Policy",
                                systemImage: "lock.shield.fill",
                                iconColor: BetterColors.brand
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    about
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.onAppear()
        }
        .refreshable {
            await viewModel.loadSettings()
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
            Text("Settings")
                .font(BetterTypography.boardDisplay)
                .foregroundStyle(Color.white)
            Text("Health sync, profile and wind-down automation")
                .font(BetterTypography.footnote)
                .foregroundStyle(BetterColors.subtext)
        }
        .padding(.top, 8)
    }

    private var profileCardSummarySection: some View {
        HStack(spacing: BetterSpacing.medium) {
            Text(profileInitial)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)
                .frame(width: 48, height: 48)
                .background(BetterColors.brandGradient)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 3) {
                Text(profileDisplayName)
                    .font(BetterTypography.title)
                    .foregroundStyle(Color.white)
                Text("\(String(format: "%.1f", viewModel.profile.sleepGoalHours))h goal · \(viewModel.profile.baselineWindowDays)-day baseline")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            
            Text(viewModel.profile.isResearchMode ? "Research" : "Standard")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((viewModel.profile.isResearchMode ? BetterColors.success : Color.white).opacity(0.12))
                .foregroundStyle(viewModel.profile.isResearchMode ? BetterColors.success : BetterColors.subtext)
                .clipShape(Capsule())
        }
        .padding(BetterSpacing.large)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var profileDisplayName: String {
        viewModel.profile.displayName?.trimmedNonEmpty ?? "Better Sleep"
    }

    private var profileInitial: String {
        let fallback = "B"
        return profileDisplayName.first.map { String($0).uppercased() } ?? fallback
    }

    private func settingsGroupHeader(title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(BetterColors.mutedText)
            .tracking(1.0)
            .padding(.leading, 4)
            .padding(.bottom, -8)
    }

    @ViewBuilder
    private func settingsGroupCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func settingsRow(
        title: String,
        subtitle: String,
        systemImage: String,
        iconColor: Color
    ) -> some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BetterTypography.subheadline.bold())
                    .foregroundStyle(Color.white)
                Text(subtitle)
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.2))
        }
        .padding(BetterSpacing.large)
        .contentShape(Rectangle())
    }

    private func settingsActionRow(
        title: String,
        systemImage: String,
        iconColor: Color
    ) -> some View {
        HStack(spacing: BetterSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            Text(title)
                .font(BetterTypography.subheadline.bold())
                .foregroundStyle(Color.white)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.2))
        }
        .padding(BetterSpacing.large)
        .contentShape(Rectangle())
    }

    private var appleHealthRow: some View {
        let isAvailable = viewModel.healthAvailability
        let statusColor = isAvailable ? BetterColors.success : BetterColors.danger
        return HStack(spacing: BetterSpacing.medium) {
            Image(systemName: isAvailable ? "heart.fill" : "heart.slash.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(statusColor)
                .frame(width: 32, height: 32)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Health")
                    .font(BetterTypography.subheadline.bold())
                    .foregroundStyle(Color.white)
                Text(isAvailable ? "Connection active" : "Access required")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
            }
            Spacer()
            
            Text(isAvailable ? "Connected" : "Disconnected")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(BetterSpacing.large)
    }

    private var about: some View {
        Text("Better Sleep · Local-first derived sleep insights")
            .font(BetterTypography.caption)
            .foregroundStyle(BetterColors.subtext)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BetterSpacing.medium)
    }
}

// MARK: - Detail Subviews

struct ProfileSettingsDetailView: View {
    @Bindable var viewModel: SettingsViewModel
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    Text("Profile settings are stored locally on this device. normalizing values will update your baseline comparison ranges.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .padding(.horizontal, 4)
                    
                    VStack(spacing: BetterSpacing.large) {
                        // Preferred Name
                        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
                            Text("Preferred Name")
                                .font(BetterTypography.footnote)
                                .foregroundStyle(Color.white.opacity(0.8))
                            
                            TextField("What can I call you?", text: bindingForDisplayName)
                                .font(BetterTypography.body)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .padding(.horizontal, BetterSpacing.medium)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        
                        // Sleep Goal
                        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
                            HStack {
                                Text("Sleep Goal").font(BetterTypography.footnote).foregroundStyle(Color.white.opacity(0.8))
                                Spacer()
                                Text(String(format: "%.1fh", viewModel.profile.sleepGoalHours))
                                    .font(BetterTypography.caption.bold())
                                    .foregroundStyle(BetterColors.brandLight)
                            }
                            Slider(value: $viewModel.profile.sleepGoalHours, in: 6...10, step: 0.25)
                                .tint(BetterColors.brandLight)
                        }
                        
                        // Baseline Window picker
                        VStack(alignment: .leading, spacing: BetterSpacing.xSmall) {
                            Text("Baseline Window").font(BetterTypography.footnote).foregroundStyle(Color.white.opacity(0.8))
                            Picker("Baseline Window", selection: $viewModel.profile.baselineWindowDays) {
                                Text("15 days").tag(15)
                                Text("30 days").tag(30)
                            }
                            .pickerStyle(.segmented)
                            .tint(BetterColors.brandLight)
                        }
                        
                        // Research Mode toggle
                        Toggle("Research Mode", isOn: $viewModel.profile.isResearchMode)
                            .font(BetterTypography.footnote)
                            .foregroundStyle(Color.white)
                            .tint(BetterColors.brandLight)
                    }
                    .padding(BetterSpacing.large)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Profile & Baseline")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            Task {
                await viewModel.saveProfile()
            }
        }
    }
    
    private var bindingForDisplayName: Binding<String> {
        Binding(
            get: { viewModel.profile.displayName ?? "" },
            set: { viewModel.profile.displayName = $0 }
        )
    }
}

struct ConnectedDevicesDetailView: View {
    let sources: [SleepSource]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    Text("The devices below have written sleep sessions read by Better Sleep in the past 30 days.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .padding(.horizontal, 4)
                    
                    VStack(spacing: BetterSpacing.medium) {
                        if sources.isEmpty {
                            Text("Sources appear after recent sleep samples are readable from Apple Health.")
                                .font(BetterTypography.footnote)
                                .foregroundStyle(BetterColors.subtext)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, BetterSpacing.large)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(sources.enumerated().map { IndexedSource(index: $0, source: $1) }) { item in
                                    HStack(spacing: BetterSpacing.medium) {
                                        Image(systemName: item.source.name.localizedCaseInsensitiveContains("watch") ? "applewatch" : "heart.text.square.fill")
                                            .foregroundStyle(BetterColors.cyan)
                                            .frame(width: 34, height: 34)
                                            .background(BetterColors.cyan.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.source.name)
                                                .font(BetterTypography.footnote.bold())
                                                .foregroundStyle(Color.white)
                                            Text(item.source.productType ?? item.source.bundleIdentifier ?? "Connected")
                                                .font(BetterTypography.caption)
                                                .foregroundStyle(BetterColors.subtext)
                                        }
                                        Spacer()
                                    }
                                    .padding(BetterSpacing.large)
                                    
                                    if item.index < sources.count - 1 {
                                        Divider().background(Color.white.opacity(0.06))
                                    }
                                }
                            }
                        }
                    }
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Connected Devices")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private struct IndexedSource: Identifiable {
        let id = UUID()
        let index: Int
        let source: SleepSource
    }
}

struct SleepModeDetailView: View {
    @Bindable var sleepModeViewModel: SleepModeViewModel
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    Text("Automate Sleep Mode schedules. When active, incoming notifications are silenced and the display aligns with low-stimulation filters.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .padding(.horizontal, 4)
                    
                    SleepModeScheduleView(viewModel: sleepModeViewModel)
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Sleep Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RedLightDetailView: View {
    @Bindable var service: RedLightFilterService
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    Text("Dim screen blue light wavelengths. This helps maintain natural melatonin production in the hours before bedtime.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .padding(.horizontal, 4)
                    
                    RedLightFilterSettingsCard(service: service)
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Red Light Filter")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DiagnosticsDetailView: View {
    @Bindable var viewModel: SettingsViewModel
    @Bindable var privacyService: PrivacyDataService
    @State private var showDeleteConfirmation = false
    @State private var showDiagnosticSheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    // Part 1: Diagnostic Run Card
                    settingsGroupHeader(title: "Biomarker Verification")
                    VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                        HStack(spacing: BetterSpacing.medium) {
                            Image(systemName: "stethoscope")
                                .foregroundStyle(BetterColors.cyan)
                                .frame(width: 38, height: 38)
                                .background(BetterColors.cyan.opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Biomarker Diagnostic")
                                    .font(BetterTypography.subheadline.bold())
                                    .foregroundStyle(Color.white)
                                Text("Checks latest sleep night sample counts and sources.")
                                    .font(BetterTypography.caption)
                                    .foregroundStyle(BetterColors.subtext)
                            }
                            Spacer()
                            Button {
                                Task {
                                    await viewModel.runBiomarkerDiagnostic()
                                    if viewModel.biomarkerDiagnosticReport != nil {
                                        showDiagnosticSheet = true
                                    }
                                }
                            } label: {
                                if viewModel.isLoadingBiomarkerDiagnostic {
                                    ProgressView()
                                        .tint(BetterColors.brandLight)
                                } else {
                                    Text("Run")
                                        .font(.system(size: 13, weight: .bold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(BetterColors.brandLight.opacity(0.12))
                                        .foregroundStyle(BetterColors.brandLight)
                                        .clipShape(Capsule())
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLoadingBiomarkerDiagnostic)
                        }
                    }
                    .padding(BetterSpacing.large)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))

                    // Part 2: Database Inventory
                    settingsGroupHeader(title: "Local Database Inventory")
                    VStack(spacing: 0) {
                        if privacyService.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, BetterSpacing.large)
                        } else if let inventory = privacyService.inventory {
                            inventoryRow(label: "Sleep sessions", value: "\(inventory.sleepSessionCount)", detail: dateRangeText(inventory))
                            Divider().background(Color.white.opacity(0.06))
                            inventoryRow(label: "Rolling baseline records", value: "\(inventory.baselineCount)")
                            Divider().background(Color.white.opacity(0.06))
                            inventoryRow(label: "Protocol baseline", value: protocolBaselineValue(inventory), detail: protocolBaselineDetail(inventory))
                            Divider().background(Color.white.opacity(0.06))
                            inventoryRow(label: "Protocol check-ins", value: "\(inventory.protocolAdherenceCount)")
                            Divider().background(Color.white.opacity(0.06))
                            inventoryRow(label: "Context check-ins", value: "\(inventory.contextEntryCount)", detail: lastContextDateText(inventory))
                            Divider().background(Color.white.opacity(0.06))
                            inventoryRow(label: "Alerts history", value: "\(inventory.alertCount)")
                            Divider().background(Color.white.opacity(0.06))
                            inventoryRow(label: "Manual biology entries", value: "\(inventory.manualBiologyEntryCount)")
                        }
                    }
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
                    .task {
                        await privacyService.loadInventory()
                    }

                    // Part 3: Destruction
                    settingsGroupHeader(title: "Danger Zone")
                    VStack {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundStyle(BetterColors.danger)
                                Text("Delete all local health data")
                                    .font(BetterTypography.subheadline.bold())
                                    .foregroundStyle(BetterColors.danger)
                                Spacer()
                            }
                            .padding(BetterSpacing.large)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(BetterColors.danger.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(BetterColors.danger.opacity(0.2), lineWidth: 1))
                    
                    Text("This removes all sleep sessions, baselines, protocol check-ins, context check-ins, and onboarding answers stored on this device. Apple Health data is unaffected.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.mutedText)
                        .padding(.horizontal, 4)
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Database & Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDiagnosticSheet) {
            if let report = viewModel.biomarkerDiagnosticReport {
                BiomarkerDiagnosticReportSheet(report: report)
            }
        }
        .alert("Delete all health data?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await privacyService.deleteAllLocalData()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all sleep sessions, baselines, protocol check-ins, context check-ins, and onboarding answers stored on this device. Apple Health data is not affected. The app will return to onboarding.")
        }
    }

    private func settingsGroupHeader(title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(BetterColors.mutedText)
            .tracking(1.0)
            .padding(.leading, 4)
            .padding(.bottom, -8)
    }

    private func inventoryRow(label: String, value: String, detail: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(BetterTypography.footnote.bold())
                    .foregroundStyle(Color.white)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(BetterColors.subtext)
                }
            }
            Spacer()
            Text(value)
                .font(BetterTypography.caption.monospacedDigit().bold())
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .padding(BetterSpacing.large)
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

struct ResearchExportDetailView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var exportDocument: ResearchExportDocument?
    @State private var showExportError = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BetterSpacing.section) {
                    Text("ZIP exports contain derived sleep, protocol, activity, biology, Body Clock, and analysis CSVs stored locally.")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .padding(.horizontal, 4)

                    exportSection
                    
                    narrativeSection
                }
                .padding(BetterSpacing.screen)
            }
        }
        .navigationTitle("Research Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportDocument) { document in
            ResearchExportDocumentPicker(url: document.url)
                .ignoresSafeArea()
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            Text("Export CSV Package")
                .font(BetterTypography.headline.bold())
                .foregroundStyle(Color.white)

            Button {
                Task {
                    await viewModel.exportRecentCSV()
                    if let exportURL = viewModel.exportURL {
                        exportDocument = ResearchExportDocument(url: exportURL)
                    } else if viewModel.errorMessage != nil {
                        showExportError = true
                    }
                }
            } label: {
                HStack(spacing: BetterSpacing.small) {
                    if viewModel.isExporting {
                        ProgressView()
                            .tint(Color.black)
                            .controlSize(.small)
                        Text("Preparing export...")
                    } else {
                        Label("Export ZIP", systemImage: "square.and.arrow.down")
                    }
                }
                .font(BetterTypography.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, BetterSpacing.medium)
                .background {
                    if viewModel.isExporting {
                        Color.white.opacity(0.12)
                    } else {
                        BetterColors.brandGradient
                    }
                }
                .foregroundStyle(viewModel.isExporting ? BetterColors.subtext : Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isExporting)

            if let exportURL = viewModel.exportURL {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BetterColors.success)
                    Text(exportURL.lastPathComponent)
                        .font(BetterTypography.caption.bold())
                        .foregroundStyle(BetterColors.success)
                }
            }
        }
        .padding(BetterSpacing.large)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    @ViewBuilder
    private var narrativeSection: some View {
        if let insightSummary = viewModel.insightSummary {
            VStack(alignment: .leading, spacing: BetterSpacing.section) {
                settingsGroupHeader(title: "Research Narrative")
                VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                    HStack {
                        Label("Research Analysis", systemImage: "chart.xyaxis.line")
                            .font(BetterTypography.subheadline.bold())
                            .foregroundStyle(Color.white)
                        Spacer()
                        Text(insightSummary.confidence.displayName)
                            .font(BetterTypography.caption)
                            .foregroundStyle(BetterColors.subtext)
                    }
                    
                    Text(insightSummary.summary)
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                        .lineSpacing(4)
                    
                    if let confounderNote = insightSummary.confounderNote {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(BetterColors.warning)
                            Text(confounderNote)
                                .font(BetterTypography.caption)
                                .foregroundStyle(BetterColors.warning)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(BetterSpacing.large)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
            }
        }
    }

    private func settingsGroupHeader(title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(BetterColors.mutedText)
            .tracking(1.0)
            .padding(.leading, 4)
            .padding(.bottom, -8)
    }
}

// MARK: - Legacy wrappers & Pickers

private struct BiomarkerDiagnosticReportSheet: View {
    let report: BiomarkerDiagnosticReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    Text(report.plainText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(BetterSpacing.screen)
                }
            }
            .navigationTitle("Biomarker Diagnostic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(BetterTypography.subheadline.bold())
                    .foregroundStyle(BetterColors.brandLight)
                }
            }
        }
    }
}

private struct ResearchExportDocument: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ResearchExportDocumentPicker: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            dismiss()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            dismiss()
        }
    }
}

#if DEBUG
#Preview("Settings") {
    let env = AppEnvironment.preview()
    SettingsTabView(
        viewModel: SettingsViewModel(
            localRepository: env.localRepository,
            healthRepository: env.healthRepository,
            syncCoordinator: env.syncCoordinator,
            privacyService: env.privacyDataService
        ),
        sleepModeViewModel: SleepModeViewModel(
            scheduleService: env.sleepModeScheduleService,
            localRepository: env.localRepository
        ),
        redLightFilterService: env.redLightFilterService,
        alertsViewModel: AlertsViewModel(
            localRepository: env.localRepository
        )
    )
}
#endif
