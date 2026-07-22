import SwiftUI

struct AppControlButton: View {
    let title: String
    let systemImage: String
    var isActive = false
    let action: () -> Void
    @Environment(\.appColors) private var appColors

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isActive ? appColors.accent : appColors.secondaryText)
        }
        .buttonStyle(.bordered)
    }
}
