import SwiftUI

struct NotificationBanner: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)
            .padding(.bottom, 16)
    }
}