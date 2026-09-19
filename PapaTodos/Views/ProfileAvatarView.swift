import SwiftUI

/// A person's avatar: their image when it loads, otherwise colored initials. Decorative
/// (hidden from VoiceOver); the surrounding view carries the person's name.
struct ProfileAvatarView: View {
    let name: String?
    let url: URL?
    @ScaledMetric private var dimension: CGFloat

    init(name: String?, url: URL?, size: CGFloat = 40) {
        self.name = name
        self.url = url
        _dimension = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.person(name))
            Text(ProfileInitials.make(from: name))
                .font(.system(size: dimension * 0.38, weight: .semibold, design: .rounded))
                // A concrete color: inside a toolbar button the hierarchical `.primary`
                // picks up the tint and the initials lose contrast on the avatar.
                .foregroundStyle(Color.primary)
                .minimumScaleFactor(0.6)
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(width: dimension, height: dimension)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
