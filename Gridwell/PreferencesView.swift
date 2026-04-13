import SwiftUI

struct PreferencesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Gridwell")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Preferences coming in a future update.")
                .foregroundStyle(.secondary)
        }
        .frame(width: 400, height: 280)
        .padding()
    }
}

#Preview {
    PreferencesView()
}
