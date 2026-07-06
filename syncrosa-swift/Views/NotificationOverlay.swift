import SwiftUI

struct NotificationMessage: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}

struct NotificationModifier: ViewModifier {
    @Binding var message: NotificationMessage?
    
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let msg = message {
                    notificationBanner(for: msg)
                        .padding(.top, 10)
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: message?.id)
    }

    private func notificationBanner(for msg: NotificationMessage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: msg.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundColor(msg.isError ? .red : .blue)

            Text(msg.text)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
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
        }
        .padding()
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SyncrosaTheme.panelBorder, lineWidth: 1)
        )
        .shadow(color: SyncrosaTheme.softShadow, radius: 10, x: 0, y: 5)
        .buttonStyle(.plain)
        .onAppear {
            // Auto-hide short status messages; progress messages keep updating until the task finishes.
            if !msg.text.contains("...") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
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
