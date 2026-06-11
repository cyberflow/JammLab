import SwiftUI

struct AppPanel<Content: View>: View {
    let content: Content
    @Environment(\.appColors) private var appColors

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.panelPadding)
            .background(appColors.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.panel))
    }
}

struct AppSectionTitle: View {
    let title: String
    @Environment(\.appColors) private var appColors

    var body: some View {
        Text(title)
            .font(AppTheme.Typography.sectionTitle)
            .foregroundStyle(appColors.primaryText)
    }
}
