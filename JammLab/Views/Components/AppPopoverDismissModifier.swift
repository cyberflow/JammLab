import SwiftUI

extension View {
    func onAppPopoverDismiss(isPresented: Bool, perform action: @escaping () -> Void) -> some View {
        modifier(AppPopoverDismissModifier(isPresented: isPresented, action: action))
    }
}

private struct AppPopoverDismissModifier: ViewModifier {
    let isPresented: Bool
    let action: () -> Void

    @State private var didPresent = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    didPresent = true
                } else if didPresent {
                    didPresent = false
                    DispatchQueue.main.async {
                        action()
                    }
                }
            }
    }
}
