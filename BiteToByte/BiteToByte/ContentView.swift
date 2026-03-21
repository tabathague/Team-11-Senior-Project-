//
//  ContentView.swift
//  BiteToByte
//
//

import SwiftUI
import CoreData

// Entity: DayLog
// Attributes:
// - id: UUID
// - date: Date (start of day)
// - createdAt: Date
// Relationship:
// - entries: To-many -> EntryLog

// Entity: EntryLog
// Attributes:
// - id: UUID
// - time: Date
// - volume: Double
// Relationship:
// - day: To-one -> DayLog

// MARK: - Persistence Controller

class PersistenceController {
    static let shared = PersistenceController()
    let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "FeedingModel")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("CoreData error: \(error)")
            }
        }
    }
}

// MARK: - Helpers

extension Date {
    func startOfDay() -> Date {
        Calendar.current.startOfDay(for: self)
    }
}

// MARK: - Data Manager

class FeedingDataManager {
    let context = PersistenceController.shared.container.viewContext

    // Get or create daily table
    func getOrCreateDayLog(for date: Date) -> DayLog {
        let day = date.startOfDay()
        let request = DayLog.fetchRequest()
        request.predicate = NSPredicate(format: "date == %@", day as NSDate)
        request.fetchLimit = 1

        if let existing = (try? context.fetch(request) as [DayLog])?.first {
            return existing
        }

        let newDay = DayLog(context: context)
        newDay.id = UUID()
        newDay.date = day
        newDay.createdAt = Date()
        save()
        return newDay
    }

    // Add entry
    func addEntry(time: Date, volume: Double) {
        let dayLog = getOrCreateDayLog(for: time)

        let entry = EntryLog(context: context)
        entry.id = UUID()
        entry.time = time
        entry.volume = volume
        entry.day = dayLog

        save()
    }

    // Auto-delete whole daily tables after 30 days
    func deleteExpiredTables() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let request = DayLog.fetchRequest()
        request.predicate = NSPredicate(format: "createdAt < %@", cutoff as NSDate)

        if let results = try? (context.fetch(request) as [DayLog]) {
            results.forEach { context.delete($0) }
            save()
        }
    }

    // Seed sample data if empty
    func seedIfNeeded() {
        let dayRequest = DayLog.fetchRequest()
        dayRequest.fetchLimit = 1
        if let count = try? context.count(for: dayRequest), count > 0 {
            return // already has data
        }

        // Create 3 days: today, -1 day, -2 days
        let days = (0..<3).compactMap { offset -> DayLog in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!.startOfDay()
            let day = DayLog(context: context)
            day.id = UUID()
            day.date = date
            day.createdAt = Date()
            return day
        }

        // Add a few entries per day
        for day in days {
            for i in 0..<4 {
                let entry = EntryLog(context: context)
                entry.id = UUID()
                entry.time = Calendar.current.date(byAdding: .hour, value: i * 3, to: day.date ?? Date())
                entry.volume = Double.random(in: 20...120)
                entry.day = day
            }
        }

        save()
    }

    func save() {
        try? context.save()
    }

    // MARK: - Export CSV
    func exportDayToCSV(dayLog: DayLog) -> URL? {
        var csv = "Time,Total Volume Delivered\n"

        // Safely cast Core Data to-many relationship (NSSet?) to Set<EntryLog>
        let entries: [EntryLog] = (dayLog.entries as? Set<EntryLog>)?
            .compactMap { $0 }
            .sorted { (lhs, rhs) in
                // Compare using optional dates safely
                let l = lhs.time ?? .distantPast
                let r = rhs.time ?? .distantPast
                return l < r
            } ?? []

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        for e in entries {
            let time = e.time ?? Date.distantPast
            let volume = e.volume
            csv += "\(formatter.string(from: time)),\(volume)\n"
        }

        // Use a safe date for filename
        let dayDate = dayLog.date ?? Date()
        let fileName = "FeedingLog_\(dayDate.timeIntervalSince1970).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Formatters
private enum Formatters {
    static let day: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    static let time: DateFormatter = {
        let tf = DateFormatter()
        tf.dateStyle = .none
        tf.timeStyle = .medium
        return tf
    }()
}

// MARK: - SwiftUI Views

struct DailyTableView: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\DayLog.date, order: .reverse)]
    ) var days: FetchedResults<DayLog>

    let manager = FeedingDataManager()

    var body: some View {
        NavigationView {
            List {
                ForEach(days, id: \.objectID) { (day: DayLog) in
                    NavigationLink(destination: EntryTableView(dayLog: day)) {
                        Text(Formatters.day.string(from: day.date ?? Date()))
                    }
                }
            }
            .navigationTitle("Daily Logs")
            .onAppear {
                manager.deleteExpiredTables() // enforce 30-day rule
                manager.seedIfNeeded()
            }
        }
    }
}

struct EntryTableView: View {
    let dayLog: DayLog
    let manager = FeedingDataManager()
    @State private var exportURL: URL? = nil
    @State private var showShareSheet = false
    var body: some View {
        VStack {
            List {
                let entriesSet = (dayLog.entries as? Set<EntryLog>) ?? []
                let entries = entriesSet.sorted { (lhs, rhs) in (lhs.time ?? .distantPast) < (rhs.time ?? .distantPast) }

                ForEach(entries, id: \.id) { (e: EntryLog) in
                    HStack {
                        Text(Formatters.time.string(from: e.time ?? .distantPast))
                        Spacer()
                        Text(String(format: "%.2f mL", e.volume))
                    }
                }
            }

            Button("Export CSV") {
                if let url = manager.exportDayToCSV(dayLog: dayLog) {
                    exportURL = url
                    showShareSheet = true
                }
            }
            .padding()
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
        .navigationTitle("Entries")
    }
}

// MARK: - App Entry
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    DailyTableView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}

