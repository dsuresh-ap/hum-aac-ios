// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Hum's web links, kept in one place so they can move to a website later.
enum HumLinks {
    static let repository = URL(string: "https://github.com/dsuresh-ap/hum-aac-ios")!
    static let privacy = URL(string: "https://github.com/dsuresh-ap/hum-aac-ios/blob/main/docs/privacy.md")!
    static let support = URL(string: "https://github.com/dsuresh-ap/hum-aac-ios/blob/main/docs/support.md")!
    static let license = URL(string: "https://github.com/dsuresh-ap/hum-aac-ios/blob/main/LICENSE")!
    static let configGuide = URL(string: "https://github.com/dsuresh-ap/hum-aac-ios/blob/main/docs/CONFIG.md")!
}

/// Settings → About Hum: version, what Hum is (and isn't), links, credits and licence.
struct AboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: Self.version)
            } header: {
                Text("Hum")
            }

            Section {
                Text("Hum is a communication tool. It is not a medical device or therapy, and it doesn't replace a speech-language pathologist.")
                Text("Don't rely on Hum as the only way to call for help in an emergency.")
            } header: {
                Text("Important")
            }

            Section {
                link("Privacy policy", systemImage: "hand.raised", url: HumLinks.privacy)
                    .accessibilityIdentifier("about.privacy")
                link("Help and support", systemImage: "questionmark.circle", url: HumLinks.support)
                link("Source code", systemImage: "chevron.left.forwardslash.chevron.right", url: HumLinks.repository)
                link("License (Apache 2.0)", systemImage: "doc.text", url: HumLinks.license)
            } header: {
                Text("Links")
            } footer: {
                Text("These open in your web browser.")
            }

            Section {
                Text(SymbolLibrary.credits).font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Symbols")
            }

            Section {
                Text("Hum is free and open source under the Apache License 2.0. It comes with no warranty.")
                Text("Apple, iCloud, Apple Intelligence, iPad, iPhone and Mac are trademarks of Apple Inc. Hum is not affiliated with or endorsed by Apple, ARASAAC or Global Symbols.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("License")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About Hum")
    }

    /// "1.0 (12)": the version and build from Info.plist.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func link(_ title: LocalizedStringKey, systemImage: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .accessibilityHint("Opens in your web browser")
        #if os(macOS)
        .help(url.absoluteString)
        #endif
    }
}
