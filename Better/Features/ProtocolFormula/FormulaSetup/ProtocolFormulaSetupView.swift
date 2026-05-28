import SwiftUI

struct ProtocolFormulaSetupView: View {
    @Bindable var viewModel: ProtocolFormulaSetupViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BetterSpacing.section) {
                header
                ForEach(viewModel.versions) { version in
                    versionRow(version)
                }
            }
            .padding(BetterSpacing.screen)
        }
        .background(BetterColors.background.ignoresSafeArea())
        .task { await viewModel.onAppear() }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Protocol versions")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(BetterColors.text)
            Text("Protocol versions are fixed so your sleep changes can be compared cleanly over time.")
                .font(.system(size: 13))
                .foregroundStyle(ProtocolPalette.mutedText)
        }
    }

    private func versionRow(_ version: ProtocolFormulaVersion) -> some View {
        let locked = viewModel.isLocked[version.id] ?? false
        return BetterHealthCard {
            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                HStack {
                    VersionChip(version: version)
                    Spacer()
                    if locked {
                        Label("Locked", systemImage: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ProtocolPalette.mutedText)
                    } else if version.isImportedPlaceholder {
                        Label("Backfill", systemImage: "pencil.tip.crop.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ProtocolPalette.addinColor)
                    }
                }
                if version.formulaText.isEmpty {
                    Text("(no formula text yet)")
                        .font(.system(size: 13))
                        .foregroundStyle(ProtocolPalette.dimText)
                } else {
                    Text(version.formulaText)
                        .font(.system(size: 14))
                        .foregroundStyle(BetterColors.text)
                }
                HStack(spacing: BetterSpacing.small) {
                    if version.isActive {
                        Text("Current")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(ProtocolPalette.versionColor(hex: version.colorHex)))
                    } else if locked {
                        Text("Tracked")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ProtocolPalette.mutedText)
                    }
                    Spacer()
                    if !version.isActive {
                        Button {
                            Task { await viewModel.setActive(version) }
                        } label: {
                            Text("Set as Current")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(ProtocolPalette.versionColor(hex: version.colorHex)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
