import SwiftUI

struct HabitCard<Menu: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.summaries) private var summaries
    let habit: Habit
    @ViewData var data: BuddyData
    /// The store's version of this habit; with one, the card redraws only when it, the habit or the day changes.
    var version: HabitVersion?
    var appearance: CardAppearance?
    var interactive = true
    /// Compared only, so cards redraw when the date changes; the parts read today's date themselves.
    var today = Day()
    var onOpen: () -> Void = {}
    var onComplete: () -> Void = {}
    /// The habit's menu, for holding the card's rows. The name and the check carry it themselves: in a lazy list,
    /// holding a button inside a menu area ran the button instead of opening the menu (iOS 27 simulator). To drag the
    /// card, the overview puts the drag around the whole card, outside these menus.
    @ViewBuilder var menu: () -> Menu
    var body: some View {
        let a=appearance ?? habit.cardAppearance(data.settings),c=BuddyStyle.color(habit.color)
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:12) {
                Button(action:onOpen) {
                    HStack(spacing:12) {
                        HabitIcon(habit:habit,size:46)
                        VStack(alignment:.leading,spacing:2) {
                            Text(habit.name).font(BuddyFont.text(17.3,.semibold)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1)
                            if a.description && !habit.detail.isEmpty { Text(habit.detail).font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme)).lineLimit(1) }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).contextMenu(menuItems:menu)
                if a.indicator { Button(action:onComplete){CompletionBadge(habit:habit,data:data)}.buttonStyle(FlatButtonStyle()).contextMenu(menuItems:menu).accessibilityLabel("Log progress for \(habit.name)").accessibilityValue(Amount.text(data.record(habit.id,Day()).amount)) }
            }.frame(height:48).padding(.horizontal,15).contentShape(Rectangle()).contextMenu(menuItems:menu)
            // The grid bleeds to the card's leading edge, where older weeks fade out.
            Group {
                if interactive {
                    ContributionHistory(habit:habit,data:data,monthLabels:a.monthLabels,weekdayLabels:a.weekdayLabels).onTapGesture(perform:onOpen).contextMenu(menuItems:menu)
                }
                else { Heatmap(habit:habit,data:data,monthLabels:a.monthLabels,weekdayLabels:a.weekdayLabels,pitch:13,fit:true) }
            }.padding(.leading,interactive && !a.weekdayLabels ? 0:15).padding(.trailing,15).padding(.top,12)
            if (a.streak || a.goal) && habit.currentGoal.cadence != .none {
                HStack(spacing:8) {
                    if a.streak { MetricChip(symbol:"flame",text:String(summaries.stats(habit,data:data).currentStreak),color:c) }
                    if a.goal { MetricChip(symbol:"target",text:habit.currentGoal.summary,color:c) }
                    Spacer()
                    if a.categoryIcons { ForEach(data.categories.filter{habit.categories.contains($0.id)}){BuddyGlyph(symbol:$0.symbol,size:14).foregroundStyle(c)} }
                }.padding(.horizontal,15).padding(.top,10).contentShape(Rectangle()).contextMenu(menuItems:menu)
            }
        }.padding(.top,15).padding(.bottom,14.7).surface(padding:0,tint:c).clipShape(RoundedRectangle(cornerRadius:24,style:.circular)).allowsHitTesting(interactive)
    }
}

extension HabitCard where Menu == EmptyView {
    /// A card without a menu, as the appearance preview and shared images draw it.
    init(habit: Habit, data: BuddyData, appearance: CardAppearance? = nil, interactive: Bool = true) {
        self.init(habit: habit, data: data, appearance: appearance, interactive: interactive) { EmptyView() }
    }
}

extension HabitCard: Equatable {
    /// Without a version every update redraws the card. Actions are left out: they act on the same habit.
    static func == (a: HabitCard, b: HabitCard) -> Bool {
        guard let version = a.version, version == b.version else { return false }
        return a.habit == b.habit && a.today == b.today && a.appearance == b.appearance && a.interactive == b.interactive
    }
}
