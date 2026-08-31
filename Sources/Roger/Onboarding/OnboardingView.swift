import AppKit
import RogerCore
import SwiftUI

/// The setup window: shows what is missing, fetches it, offers the relaunch. The
/// one window deliberately in system appearance — a request for permissions
/// should look like a macOS dialog; the field-radio housing starts after it.
struct OnboardingView: View {
    let model: OnboardingModel
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 0) {
                ForEach(Array(OnboardingModel.Requirement.allCases.enumerated()), id: \.element) { index, requirement in
                    if index > 0 { Divider().padding(.leading, 60) }
                    RequirementRow(
                        requirement: requirement,
                        status: model.status(of: requirement),
                        onRequest: { model.request(requirement) }
                    )
                }
            }
            Divider()
            footer
        }
        .frame(width: 460)
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 14) {
            // The real app icon, so it is recognisable right after installing.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("Roger einrichten")
                    .font(.system(size: 16, weight: .semibold))
                Text("Zwei Freigaben, dann kannst du diktieren.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            statusText
            Spacer()
            if model.needsRelaunch {
                Button("Roger neu starten") { model.relaunch() }
                    .keyboardShortcut(.defaultAction)
            } else if model.snapshot.isComplete {
                Button("Los geht's", action: onFinish)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var statusText: some View {
        if model.needsRelaunch {
            Label(
                "Erteilte Berechtigungen greifen erst nach einem Neustart.",
                systemImage: "arrow.clockwise"
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        } else if model.snapshot.isComplete {
            Label("Alles bereit", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        }
    }
}

private struct RequirementRow: View {
    let requirement: OnboardingModel.Requirement
    let status: PermissionStatus
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: requirement.symbolName)
                .font(.system(size: 15))
                .foregroundStyle(status.isGranted ? Color.green : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(requirement.title)
                    .font(.system(size: 13, weight: .medium))
                Text(requirement.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if status.isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
            } else {
                Button(buttonTitle, action: onRequest)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .animation(.easeOut(duration: 0.2), value: status)
    }

    private var buttonTitle: String {
        status == .notDetermined ? "Erlauben" : "Einstellungen öffnen"
    }
}
