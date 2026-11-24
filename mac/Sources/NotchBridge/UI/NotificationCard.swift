import AppKit
import SwiftUI

/// The phone-notification card. Fixed size: every notification, with or without actions, short or long,
/// hovered or not, has exactly the same footprint, so the island never jumps.
///
///   ┌────────────────────────────────────────┐  ← strip beside the camera (app icon · time)
///   │ (avatar)  Title                    ✕   │  row: fixed 40 pt
///   │           Text, always 2 lines         │
///   │ [Reply] [Action]              [Clear]  │  row: fixed 26 pt (or reply field / status)
///   │ ─────────────── countdown ──────────── │
///   └────────────────────────────────────────┘
struct NotificationCard: View {
    @ObservedObject var model: IslandModel
    let n: PhoneNotification
    let accent: Color
    let ns: Namespace.ID
    @FocusState private var replyFocused: Bool

    static let contentRowHeight: CGFloat = 48
    static let actionRowHeight: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(n: n, size: 34, badge: true, appIcon: model.appIcon(n.pkg), accent: model.accent(n.pkg))
                    .matchedGeometryEffect(id: "avatar", in: ns)
                    .overlay(Circle().stroke(accent.opacity(0.9), lineWidth: 1.4).padding(-2.5))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(n.title.isEmpty ? n.app : n.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        // Always laid out (only faded) so hovering never shifts anything.
                        CloseButton { model.onCloseActivity() }
                            .opacity(model.hovering ? 1 : 0)
                            .allowsHitTesting(model.hovering)
                    }
                    Text(n.text.isEmpty ? " " : n.text)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .frame(height: Self.contentRowHeight, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { model.onOpenNotification(n) }
            .help("Click to open it in the Phone tab")

            ZStack(alignment: .leading) {
                if let feedback = model.feedback {
                    HStack(spacing: 7) {
                        Image(systemName: model.feedbackIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        Text(feedback).lineLimit(1)
                    }
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.feedbackIsError ? Color.orange : Color.green)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                } else if model.replying, let reply = n.replyAction {
                    replyField(reply)
                        .transition(.opacity)
                } else {
                    actionRow
                        .transition(.opacity)
                }
            }
            .frame(height: Self.actionRowHeight)

            CountdownBar(deadline: model.hideDeadline, duration: model.hideDuration, color: accent)
        }
        .padding(.horizontal, 13)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .animation(.easeOut(duration: 0.18), value: model.replying)
        .animation(.easeOut(duration: 0.18), value: model.feedback)
        .animation(.easeOut(duration: 0.15), value: model.hovering)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            if n.replyAction != nil {
                IslandButton(title: "Reply", icon: "arrowshape.turn.up.left.fill", style: .primary(accent)) {
                    model.replying = true
                    model.onExpandCard()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { replyFocused = true }
                }
            }
            ForEach(n.buttonActions.prefix(1), id: \.self) { a in
                IslandButton(title: a.title, icon: nil, style: .secondary) { model.onAction(n, a) }
            }
            Spacer(minLength: 0)
            IslandButton(title: "Clear", icon: "xmark", style: .destructive) { model.onDismiss(n) }
                .help("Dismiss on the phone too")
        }
    }

    private func replyField(_ action: WireAction) -> some View {
        let empty = model.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            TextField("", text: $model.replyText, prompt: Text(action.title.isEmpty ? "Reply…" : "\(action.title)…")
                .foregroundStyle(.white.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white)
                .focused($replyFocused)
                .onSubmit { send(action) }
                .onExitCommand { model.replying = false }
            Button { send(action) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(empty ? .white.opacity(0.4) : .black)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(empty ? Color.white.opacity(0.12) : accent))
            }
            .buttonStyle(.plain)
            .disabled(empty)
        }
        .padding(.leading, 11)
        .padding(.trailing, 2)
        .frame(height: Self.actionRowHeight)
        .background(Capsule().fill(.white.opacity(0.09)))
        .overlay(Capsule().stroke(accent.opacity(replyFocused ? 0.6 : 0.15), lineWidth: 1))
    }

    private func send(_ action: WireAction) {
        let text = model.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.onReply(n, action, text)
        model.replyText = ""
        model.replying = false
    }
}
