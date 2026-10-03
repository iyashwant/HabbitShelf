import SwiftUI

struct HabitCard: View {
    let habit: Habit
    let data: BuddyData
    var appearance: CardAppearance?
    var interactive = true
    var onOpen: () -> Void = {}
    var onComplete: () -> Void = {}
    var body: some View {
        let a=appearance ?? habit.cardAppearance(data.settings),c=BuddyStyle.color(habit.color)
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:10) {
                Button(action:onOpen) {
                    HStack(spacing:10) {
                        HabitIcon(habit:habit)
                        VStack(alignment:.leading,spacing:3) {
                            Text(habit.name).font(.system(size:14,weight:.semibold)).foregroundStyle(.primary)
                            if a.description && !habit.detail.isEmpty { Text(habit.detail).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1) }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }.buttonStyle(.plain)
                if a.indicator { Button(action:onComplete){CompletionBadge(habit:habit,data:data).padding(2)}.buttonStyle(.plain).accessibilityLabel("Log progress for \(habit.name)").accessibilityValue(Amount.text(data.record(habit.id,Day()).amount)) }
            }
            if interactive { ContributionHistory(habit:habit,data:data,monthLabels:a.monthLabels,weekdayLabels:a.weekdayLabels).onTapGesture(perform:onOpen) }
            else { Heatmap(habit:habit,data:data,monthLabels:a.monthLabels,weekdayLabels:a.weekdayLabels) }
            if (a.streak || a.goal) && habit.currentGoal.cadence != .none {
                HStack(spacing:6) {
                    if a.streak { MetricChip(symbol:"flame.fill",text:String(Engine.stats(habit,data:data).currentStreak),color:c) }
                    if a.goal { MetricChip(symbol:"target",text:habit.currentGoal.summary,color:c) }
                    Spacer()
                    if a.categoryIcons { ForEach(data.categories.filter{habit.categories.contains($0.id)}){BuddyGlyph(symbol:$0.symbol,size:12).foregroundStyle(c)} }
                }
            }
        }.surface(tint:c).allowsHitTesting(interactive)
    }
}
