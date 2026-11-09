import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: EventStore
    @EnvironmentObject private var router: Router
    @State private var filter = Filter.warnings

    enum Filter: String, CaseIterable { case warnings = "Warnings", all = "Everything" }

    private var shown: [MessageEvent] {
        filter == .all ? store.events : store.events.filter(\.isWarning)
    }

    private var days: [(Date, [MessageEvent])] {
        let groups = Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.receivedAt) }
        return groups.sorted { $0.key > $1.key }
    }

    var body: some View {
        List {
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

            if shown.isEmpty {
                VStack(spacing: 12) {
                    KittenView(mood: .sleeping, size: 90)
                    Text(filter == .warnings ? "No warnings yet" : "No messages checked yet").font(.headline)
                    Text("Messages Stead checks will show up here.").foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }

            ForEach(days, id: \.0) { day, events in
                Section {
                    ForEach(events) { event in
                        Button { router.openEvent = event.id } label: { EventRow(event: event) }
                            .listRowBackground(Theme.surface)
                    }
                } header: {
                    Text(dayTitle(day)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Activity")
        .refreshable { store.reload() }
    }

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }
}
