import AppKit
import SwiftUI

/// The full phone-notification card (activity, stage .full).
struct NotificationCard: View {
    @ObservedObject var model: IslandModel
    let n: PhoneNotification
    let accent: Color
    let ns: Namespace.ID
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                AvatarView(n: n, size: 34, badge: true, appIcon: model.appIcon(n.pkg), accent: model.accent(n.pkg))
                    .matchedGeometryEffect(id: "avatar", in: ns)
                    .overlay(Circle().stroke(
                        AngularGradient(colors: [accent, accent.opacity(0.2), accent], center: .center),
                        lineWidth: 1.4).padding(-2.5))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(n.title.isEmpty ? n.app : n.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if model.hovering || model.expanded {
                            CloseButton { model.onCloseActivity() }
                                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                        }
                    }
                    if !n.text.isEmpty {
                        Text(n.text)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(model.expanded ? 8 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let sub = n.sub, !sub.isEmpty, model.expanded {
                        Text(sub).font(.system(size: 10.5, design: .rounded)).foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { model.expanded.toggle() }
                if model.expanded { model.onExpandCard() }
            }

            if let feedback = model.feedback {
                HStack(spacing: 7) {
                    Image(systemName: model.feedbackIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(feedback)
                }
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(model.feedbackIsError ? Color.orange : Color.green)
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if model.replying, let reply = n.replyAction {
                replyField(reply)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if model.expanded {
                actionRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if model.hovering {
                Text("Click for actions · swipe up to hide")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            CountdownBar(deadline: model.hideDeadline, duration: model.hideDuration, color: accent)
        }
        .padding(.horizontal, 13)
        .padding(.top, 5)
        .padding(.bottom, 9)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: model.replying)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: model.feedback)
        .animation(.easeOut(duration: 0.2), value: model.hovering)
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
        .padding(.trailing, 3)
        .padding(.vertical, 3)
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
