import SwiftUI

enum BuddyStyle {
    static let purple = Color(red: 0.56, green: 0.50, blue: 0.97)
    static let colors: [(String, UInt32)] = [
        ("coral",0xFF6B75), ("orange",0xFF9E43), ("amber",0xFFBF31), ("yellow",0xFFD32A),
        ("lime",0xA8E62E), ("green",0x45D979), ("mint",0x29CDA0),
        ("teal",0x29C6B7), ("cyan",0x27CBE4), ("sky",0x37B5EE), ("blue",0x629CE9),
        ("indigo",0x8884F5), ("lavender",0xAE88F4), ("violet",0xBC6CEA),
        ("magenta",0xD775ED), ("pink",0xF583B8), ("rose",0xF06386), ("slate",0x8696A8),
        ("steel",0xABB3BE), ("gray",0xB1B1AD), ("stone",0xA7A49F)
    ]
    static let symbols = ["leaf.fill", "heart.fill", "dumbbell.fill", "book.closed.fill", "drop.fill", "figure.walk", "moon.fill", "sun.max.fill", "pencil.tip", "laptopcomputer", "cup.and.saucer.fill", "fork.knife", "brain.head.profile", "guitars.fill", "music.note", "paintbrush.fill", "flame.fill", "bolt.fill", "bed.double.fill", "figure.mind.and.body", "cross.case.fill", "pill.fill", "carrot.fill", "hands.clap.fill", "bicycle", "figure.run", "code", "wallet.pass.fill", "phone.down.fill", "nosign", "smoke.fill", "gamecontroller.fill", "camera.fill", "dog.fill", "house.fill", "sparkles", "checkmark", "star.fill", "globe", "water.waves"]
    static func color(_ token: String) -> Color {
        let n = colors.first { $0.0 == token }?.1 ?? 0x29CDA0
        return Color(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
}
struct Surface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.padding(16).background(scheme == .dark ? Color(white: 0.105) : Color(white: 0.95), in: RoundedRectangle(cornerRadius: 22))
    }
}
extension View { func surface() -> some View { modifier(Surface()) } }
struct HabitIcon: View {
    let habit: Habit
    var size: CGFloat = 42
    var body: some View {
        Group {
            if habit.symbol.contains(where: { $0.isEmojiPresentation }) { Text(habit.symbol).font(.system(size: size * 0.48)) }
            else { Image(systemName: habit.symbol).font(.system(size: size * 0.42, weight: .semibold)) }
        }
        .foregroundStyle(BuddyStyle.color(habit.color)).frame(width: size, height: size)
        .background(BuddyStyle.color(habit.color).opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28))
        .accessibilityHidden(true)
    }
}
private extension Character {
    var isEmojiPresentation: Bool { unicodeScalars.contains { $0.properties.isEmojiPresentation } }
}
struct MetricChip: View {
    var symbol: String
    var text: String
    var color: Color
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(color).background(color.opacity(0.12), in: Capsule())
    }
}
struct CompletionBadge: View {
    let habit: Habit
    let data: BuddyData
    var day = Day()
    var size: CGFloat = 44
    var body: some View {
        let p = Engine.progress(habit, day: day, data: data), color = BuddyStyle.color(habit.color)
        let numeric = habit.goal(on: day).tracking != .yesNo
        ZStack {
            if numeric {
                Circle().stroke(color.opacity(0.16), lineWidth: 2)
                Circle().trim(from: 0, to: p.fraction).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
            } else { RoundedRectangle(cornerRadius: size * 0.3).fill(color.opacity(p.success ? 1 : 0.13)) }
            Image(systemName: p.slip ? "xmark" : p.success ? "checkmark" : "plus")
                .font(.system(size: size * 0.46, weight: .medium)).foregroundStyle(p.success && !numeric ? Color.black.opacity(0.7) : color)
        }.frame(width: size, height: size)
    }
}
extension Goal {
    var summary: String {
        if mode == .quit { return tracking == .yesNo ? "Quit · Daily" : "Below \(Amount.text(target)) \(unit)" }
        switch cadence {
        case .none: return "No streak goal"
        case .daily: return "Daily"
        case .weekly: return "\(days) / Week"
        case .monthly: return "\(days) / Month"
        }
    }
}
