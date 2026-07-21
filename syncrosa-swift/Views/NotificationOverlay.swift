import SwiftUI

struct NotificationMessage: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
    let dismissAfter: TimeInterval?

    init(text: String, isError: Bool, dismissAfter: TimeInterval? = nil) {
        self.text = text
        self.isError = isError
        self.dismissAfter = dismissAfter ?? (isError ? nil : 4)
    }
}

struct NotificationModifier: ViewModifier {
    @Binding var message: NotificationMessage?
    
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let msg = message {
                    notificationBanner(for: msg)
                        .padding(.top, 14)
                        .padding(.horizontal, 28)
                        .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .animation(.easeOut(duration: 0.18), value: message?.id)
    }

    private func notificationBanner(for msg: NotificationMessage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: msg.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(msg.isError ? SyncrosaTheme.destructive : SyncrosaTheme.accent)

            Text(msg.text)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: {
                withAnimation {
                    message = nil
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(SyncrosaGlassIconButtonStyle(size: 28))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: SyncrosaTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SyncrosaTheme.cardRadius, style: .continuous)
                .stroke(SyncrosaTheme.panelBorder.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: SyncrosaTheme.softShadow, radius: 18, x: 0, y: 8)
        .onAppear {
            if let dismissAfter = msg.dismissAfter {
                DispatchQueue.main.asyncAfter(deadline: .now() + dismissAfter) {
                    withAnimation {
                        if message?.id == msg.id {
                            message = nil
                        }
                    }
                }
            }
        }
    }
}

// Helper for blurred background on macOS
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension View {
    func notification(message: Binding<NotificationMessage?>) -> some View {
        self.modifier(NotificationModifier(message: message))
    }
}
