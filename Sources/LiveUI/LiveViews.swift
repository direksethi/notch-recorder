import Common
import SwiftUI

private extension AudioSource {
    var label: String {
        switch self {
        case .me: "Me"
        case .others: "Others"
        case .speaker: "Speaker"
        }
    }

    var color: Color { self == .me ? Theme.speakerMe : Theme.speakerOthers }
}

struct RecordingDot: View {
    var paused: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(paused ? Theme.warning : Theme.recording)
            .frame(width: 8, height: 8)
            .opacity(pulse && !paused ? 0.45 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

struct LevelMeter: View {
    var source: AudioSource
    var level: Float

    var body: some View {
        HStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let scale = CGFloat(min(1, Double(level) * 6 * [0.7, 1.0, 0.8][i]))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(source.color)
                        .frame(width: 3, height: 3 + 9 * scale)
                }
            }
            .frame(height: 12, alignment: .bottom)
            .animation(.easeOut(duration: 0.12), value: level)
            Text(source.label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
        }
    }
}

struct ActionButton: View {
    enum Role { case primary, secondary, destructive }
    var title: String
    var role: Role
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .foregroundStyle(Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(
                        role == .primary ? Theme.messageAction : role == .destructive ? Theme.recording : Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
    }
}

struct LineView: View {
    var source: AudioSource
    var text: String
    var partial: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(source.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(source.color.opacity(partial ? 0.6 : 1))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(partial ? Theme.textMuted : Theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Timer, meters and Stop on top; the running transcript below.
struct RecordingView: View {
    @Bindable var model: LiveModel

    private var status: String {
        switch model.phase {
        case .paused: "Paused during sleep"
        case .finishing: "Saving recording…"
        default: "Recording"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if model.phase == .finishing {
                    ProgressView().controlSize(.mini)
                } else {
                    RecordingDot(paused: model.phase == .paused)
                }
                Text(LiveModel.clock(model.elapsed))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.text)
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                Spacer(minLength: 8)
                LevelMeter(source: .me, level: model.meLevel)
                LevelMeter(source: .others, level: model.othersLevel)
                ActionButton(title: "Stop", role: .destructive) { model.onStop() }
                    .disabled(model.phase == .finishing)
                    .opacity(model.phase == .finishing ? 0.5 : 1)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            if let warning = model.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.warningForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            Rectangle().fill(Theme.border).frame(height: 0.5)
            TranscriptList(model: model)
        }
    }
}

struct TranscriptList: View {
    @Bindable var model: LiveModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.lines.isEmpty && model.partials.isEmpty {
                        Text(model.transcriptNote ?? "Listening for speech…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textMuted)
                    }
                    ForEach(model.lines) { line in
                        LineView(source: line.source, text: line.text, partial: false)
                    }
                    if model.showPartials {
                        ForEach(AudioSource.allCases, id: \.self) { source in
                            if let text = model.partials[source] {
                                LineView(source: source, text: text, partial: true)
                            }
                        }
                    }
                    if let note = model.transcriptNote, !(model.lines.isEmpty && model.partials.isEmpty) {
                        Text(note).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(14)
            }
            .onChange(of: model.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.partials) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}

struct PreparingView: View {
    @Bindable var model: LiveModel

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Loading transcription model…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
            Text("Recording starts when the model is ready. The first load after an update can take about a minute.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ActionButton(title: "Cancel", role: .secondary) { model.onCancel() }
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoticeView: View {
    var title: String
    var message: String
    @Bindable var model: LiveModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.warningForeground)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                ActionButton(title: "Open Library", role: .secondary) { model.onOpenLibrary() }
                ActionButton(title: "Close", role: .primary) { model.onClose() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

public struct LiveRootView: View {
    @Bindable var model: LiveModel

    public init(model: LiveModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.phase {
            case .hidden:
                Color.clear
            case .preparing:
                PreparingView(model: model)
            case .notice(let title, let message):
                NoticeView(title: title, message: message, model: model)
            case .recording, .paused, .finishing:
                RecordingView(model: model)
            }
        }
        .frame(minWidth: 380, minHeight: 240)
        .background(Theme.canvas)
        .preferredColorScheme(.dark)
    }
}
