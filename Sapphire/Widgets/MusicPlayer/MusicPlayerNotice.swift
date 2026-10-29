import SwiftUI

struct MusicPlayerNotice: View {
    static let contentWidth: CGFloat = 400
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: Self.contentWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
