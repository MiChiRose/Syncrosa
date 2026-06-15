import SwiftUI

struct NotificationMessage: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}

struct NotificationModifier: ViewModifier {
    @Binding var message: NotificationMessage?
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if let msg = message {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: msg.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .foregroundColor(msg.isError ? .red : .blue)
                        
                        Text(msg.text)
                            .font(.system(size: 14, weight: .medium))
                        
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
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                    .padding(.top, 20)
                    .padding(.horizontal, 40)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        // Auto-hide after 3 seconds unless it's a long process
                        if !msg.text.contains("...") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation {
                                    message = nil
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                .zIndex(100)
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
