import SwiftUI
import SISRKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppAppearancePreference.allCases) { pref in
                        Text(pref.title).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                PanelSectionHeader(title: "Appearance", systemImage: "circle.lefthalf.filled")
            } footer: {
                Text("The viewer canvas stays near-black so exposure and color grade accurately.")
            }

            Section {
                HStack {
                    Text("Frame rate")
                    Spacer()
                    TextField("", value: $settings.defaultFPS, format: .number)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                    Text("fps")
                        .foregroundStyle(.secondary)
                }

                Picker("Codec", selection: $settings.defaultCodec) {
                    ForEach(OutputCodec.allCases) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }

                HStack {
                    Text("Preview cache")
                    Spacer()
                    TextField("", value: $settings.previewCacheLimit, format: .number)
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                    Text("frames")
                        .foregroundStyle(.secondary)
                }
            } header: {
                PanelSectionHeader(title: "Defaults", systemImage: "gearshape")
            } footer: {
                Text("Applied when you open a new sequence.")
            }

            Section {
                Toggle("Notify when render finishes", isOn: $settings.notifyOnRenderComplete)
            } header: {
                PanelSectionHeader(title: "Notifications", systemImage: "bell")
            } footer: {
                Text("macOS may ask once for permission the first time a render completes with this enabled.")
            }

            Section {
                Button("Mac user guide") { SiteLinks.open(SiteLinks.macGuide) }
                Button("Support") { SiteLinks.open(SiteLinks.support) }
                Button("Privacy policy") { SiteLinks.open(SiteLinks.privacy) }
            } header: {
                PanelSectionHeader(title: "Help & legal", systemImage: "questionmark.circle")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 460)
    }
}
