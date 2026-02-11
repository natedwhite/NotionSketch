import SwiftUI

/// Settings screen for configuring Notion API credentials.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = SettingsManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("API Token", systemImage: "key.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        SecureField("ntn_...", text: $settings.apiToken)
                            .textContentType(.password)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Notion Integration")
                } footer: {
                    Text("Create an integration at notion.so/profile/integrations and paste the Internal Integration Secret here.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Database", systemImage: "tray.full.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("Paste database URL or ID…", text: $settings.databaseInput)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        if !settings.databaseID.isEmpty && settings.databaseInput != settings.databaseID {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .imageScale(.small)
                                Text("ID: \(settings.databaseID)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Paste the full Notion database URL — the database ID will be extracted automatically. Make sure your integration is connected to this database.")
                }


                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Short.io API Key", systemImage: "link")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        SecureField("Paste API Key...", text: $settings.shortIoApiKey)
                            .textContentType(.password)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Short.io Domain", systemImage: "globe")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        TextField("short.gy", text: $settings.shortIoDomain)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Deep Link Shortener")
                } footer: {
                    Text("Enter your Short.io API key for ad-free links (1,000 free). Get a key at short.io. Leave blank to use TinyURL.")
                }

                Section {
                    HStack {
                        Image(systemName: settings.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(settings.isConfigured ? .green : .orange)
                            .font(.title3)

                        Text(settings.isConfigured ? "Ready to sync" : "Enter both fields to enable syncing")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    DisclosureGroup("Sync Log") {
                        ScrollView {
                            Text(syncLogText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 300)

                        HStack {
                            Button("Copy Log") {
                                UIPasteboard.general.string = syncLogText
                            }
                            .buttonStyle(.bordered)

                            Button("Refresh") {
                                syncLogText = SyncLogger.readLog()
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button("Clear", role: .destructive) {
                                SyncLogger.clearLog()
                                syncLogText = "(cleared)"
                            }
                            .buttonStyle(.bordered)
                        }
                        .font(.caption)
                    }
                } header: {
                    Text("Debug")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                syncLogText = SyncLogger.readLog()
            }
        }
    }

    @State private var syncLogText: String = ""
}

#Preview {
    SettingsView()
}
