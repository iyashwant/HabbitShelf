import SwiftUI

struct HabitCard: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.summaries) private var summaries
    let habit: Habit
    let data: BuddyData
    var appearance: CardAppearance?
    var interactive = true
    var onOpen: () -> Void = {}
    var onComplete: () -> Void = {}
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
                }.buttonStyle(.plain)
                if a.indicator { Button(action:onComplete){CompletionBadge(habit:habit,data:data)}.buttonStyle(.plain).accessibilityLabel("Log progress for \(habit.name)").accessibilityValue(Amount.text(data.record(habit.id,Day()).amount)) }
            }.frame(height:48).padding(.horizontal,15)
            // The grid bleeds to the card's leading edge, where older weeks fade out.
            Group {
                if interactive { ContributionHistory(habit:habit,data:data,monthLabels:a.monthLabels,weekdayLabels:a.weekdayLabels).onTapGesture(perform:onOpen) }
                else { Heatmap(habit:habit,data:data,monthLabels:a.monthLabels,weekdayLabels:a.weekdayLabels,pitch:13,fit:true) }
            }.padding(.leading,interactive && !a.weekdayLabels ? 0:15).padding(.trailing,15).padding(.top,12)
            if (a.streak || a.goal) && habit.currentGoal.cadence != .none {
                HStack(spacing:8) {
                    if a.streak { MetricChip(symbol:"flame",text:String(summaries.stats(habit,data:data).currentStreak),color:c) }
                    if a.goal { MetricChip(symbol:"target",text:habit.currentGoal.summary,color:c) }
                    Spacer()
                    if a.categoryIcons { ForEach(data.categories.filter{habit.categories.contains($0.id)}){BuddyGlyph(symbol:$0.symbol,size:14).foregroundStyle(c)} }
                }.padding(.horizontal,15).padding(.top,10)
            }
        }.padding(.top,15).padding(.bottom,14.7).surface(padding:0,tint:c).clipShape(RoundedRectangle(cornerRadius:24,style:.circular)).allowsHitTesting(interactive)
    }
}
