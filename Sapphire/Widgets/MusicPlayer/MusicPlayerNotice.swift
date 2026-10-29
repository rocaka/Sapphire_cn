import SwiftUI

struct MusicPlayerNotice: View {
    static let contentWidth: CGFloat = 400
    let message: String
    var width: CGFloat = Self.contentWidth

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
