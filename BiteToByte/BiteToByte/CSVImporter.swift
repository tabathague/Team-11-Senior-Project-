import Foundation
import CoreData

// MARK: - CSV Row Model
struct CSVRow {
    let timestamp: Date
    let flowRate: Double   // mL/hr
}

//// MARK: - Flow Rate Parser
//func parseFlowRate(_ raw: String) -> Double? {
//    if raw.lowercased().contains("none") { return nil }
//    
//    let cleaned = raw.replacingOccurrences(of: "_", with: "")
//    return Double(cleaned)
//}

// MARK: - Updated Flow Rate Parser
func parseFlowRate(_ raw: String) -> Double? {
    // Handle "NA", "Not feeding", or "none"
    let lower = raw.lowercased()
    if lower.contains("none") || lower.contains("not") || lower.contains("invalid") || lower.contains("na") {
        return nil
    }
    
    let cleaned = raw.replacingOccurrences(of: "_", with: "")
    return Double(cleaned)
}

// MARK: - Load CSV from App Bundle
func loadCSV(named fileName: String) -> String? {
    guard let path = Bundle.main.path(forResource: fileName, ofType: "csv") else {
        print("CSV not found")
        return nil
    }
    
    do {
        let content = try String(contentsOfFile: path)
        print("CSV loaded")
        return content
    } catch {
        print("Error loading CSV:", error)
        return nil
    }
}

//// MARK: - Parse CSV into Rows
//func parseCSV(_ csvString: String) -> [CSVRow] {
//    var results: [CSVRow] = []
//    
//    let rows = csvString.components(separatedBy: "\n")
//    
//    let formatter = ISO8601DateFormatter()
//    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
//    
//    for (index, row) in rows.enumerated() {
//        if index == 0 { continue } // skip header
//        if row.trimmingCharacters(in: .whitespaces).isEmpty { continue }
//        
//        let columns = row.components(separatedBy: ",")
//        if columns.count < 4 { continue }
//        
//        let timestampString = columns[0]
//        let rawDigits = columns[3]
//        
//        guard let date = formatter.date(from: timestampString),
//              let flow = parseFlowRate(rawDigits) else {
//            continue
//        }
//        
//        results.append(CSVRow(timestamp: date, flowRate: flow))
//    }
//    
//    print("Parsed \(results.count) rows")
//    return results
//}

// MARK: - Bulletproof CSV Parser
func parseCSV(_ csvString: String) -> [CSVRow] {
    var results: [CSVRow] = []
    
    // 1. Handle all types of line breaks (\n, \r, or \r\n)
    let rows = csvString.components(separatedBy: .newlines)
    
    // 2. Setup Formatters for your specific CSV dates
    // Formatter for: 2026-04-09T21:21:08.558734
    let isoHighPrecision = DateFormatter()
    isoHighPrecision.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
    
    // Formatter for: 2026-04-09 14:22:40
    let standardDate = DateFormatter()
    standardDate.dateFormat = "yyyy-MM-dd HH:mm:ss"
    
    for (index, row) in rows.enumerated() {
        // Skip header and empty rows
        if index == 0 || row.trimmingCharacters(in: .whitespaces).isEmpty { continue }
        
        let columns = row.components(separatedBy: ",")
        guard columns.count >= 4 else { continue }
        
        let timestampString = columns[0].trimmingCharacters(in: .whitespaces)
        let rawDigits = columns[3].trimmingCharacters(in: .whitespaces)
        
        // 3. Try to parse the date using both possible formats
        guard let date = isoHighPrecision.date(from: timestampString) ?? standardDate.date(from: timestampString) else {
            print("Skipping row \(index): Date format mismatch (\(timestampString))")
            continue
        }
        
        // 4. Parse the flow rate (handles the underscores like 2_5_8)
        if let flow = parseFlowRate(rawDigits) {
            results.append(CSVRow(timestamp: date, flowRate: flow))
        } else {
            print("Skipping row \(index): No valid flow rate in \(rawDigits)")
        }
    }
    
    print("Parsed \(results.count) valid data rows successfully")
    return results
}

//// MARK: - Save to Core Data with Volume Calculation
//func saveRows(_ rows: [CSVRow], context: NSManagedObjectContext) {
//    
//    var dayCache: [Date: DayLog] = [:]
//    var cumulativeVolume: Double = 0
//    
//    for i in 1..<rows.count {
//        let current = rows[i]
//        let previous = rows[i - 1]
//        
//        let deltaT = current.timestamp.timeIntervalSince(previous.timestamp) / 3600.0
//        if deltaT <= 0 { continue }
//        
//        // Volume = flow rate × time
//        let deltaV = previous.flowRate * deltaT
//        cumulativeVolume += deltaV
//        
//        // Optional: reset per day
//        if !Calendar.current.isDate(current.timestamp, inSameDayAs: previous.timestamp) {
//            cumulativeVolume = deltaV
//        }
//        
//        let dayDate = Calendar.current.startOfDay(for: current.timestamp)
//        
//        let dayLog: DayLog
//        if let existing = dayCache[dayDate] {
//            dayLog = existing
//        } else {
//            let newDay = DayLog(context: context)
//            newDay.id = String()
//            newDay.name = String()
//            newDay.date = dayDate
//            newDay.createdAt = Date()
//            dayCache[dayDate] = newDay
//            dayLog = newDay
//        }
//        
//        let entry = EntryLog(context: context)
//        entry.id = String()
//        entry.name = String()
//        entry.time = current.timestamp
//        entry.volume = cumulativeVolume   // cumulative volume
//        entry.day = dayLog
//    }
//    
//    do {
//        try context.save()
//        print("Data saved to Core Data")
//    } catch {
//        print("Error saving:", error)
//    }
//}

func saveRows(_ rows: [CSVRow], context: NSManagedObjectContext, patientID: String, patientName: String) {
    var cumulativeVolume: Double = 0
    
    for i in 1..<rows.count {
        let current = rows[i]
        let previous = rows[i - 1]
        
        let deltaT = current.timestamp.timeIntervalSince(previous.timestamp) / 3600.0
        if deltaT <= 0 { continue }
        
        let deltaV = previous.flowRate * deltaT
        cumulativeVolume += deltaV
        
        if !Calendar.current.isDate(current.timestamp, inSameDayAs: previous.timestamp) {
            cumulativeVolume = deltaV
        }
        
        let dayDate = Calendar.current.startOfDay(for: current.timestamp)
        
        // --- FIX: Check if this DayLog already exists for THIS patient ---
        let request: NSFetchRequest<DayLog> = DayLog.fetchRequest()
        // Match both the Date AND the Patient ID
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "date == %@", dayDate as NSDate),
            NSPredicate(format: "id == %@", patientID)
        ])
        
        let dayLog: DayLog
        if let existingDay = (try? context.fetch(request))?.first {
            dayLog = existingDay
        } else {
            dayLog = DayLog(context: context)
            dayLog.id = patientID
            dayLog.name = patientName
            dayLog.date = dayDate
            dayLog.createdAt = Date()
        }
        
        let entry = EntryLog(context: context)
        entry.id = UUID().uuidString
        entry.name = patientName
        entry.time = current.timestamp
        entry.volume = cumulativeVolume
        entry.day = dayLog // This links the entry to the day
    }
    
    try? context.save()
}

// MARK: - Main Import Function
//func importCSVIntoCoreData(context: NSManagedObjectContext) {
//    
//    guard let csvString = loadCSV(named: "feeding_rates") else { return }
//    
//    let rows = parseCSV(csvString)
//    
//    guard !rows.isEmpty else {
//        print("No valid data parsed")
//        return
//    }
//    
//    saveRows(rows, context: context)
//}
// MARK: - Main Import Function (Update this one!)
func importCSVIntoCoreData(context: NSManagedObjectContext, id: String, name: String) {
    
    guard let csvString = loadCSV(named: "feeding_rates") else {
        print("Failed to load CSV string")
        return
    }
    
    let rows = parseCSV(csvString)
    
    guard !rows.isEmpty else {
        print("No valid data parsed from CSV")
        return
    }
    
    // Pass the id and name through to the save function
    saveRows(rows, context: context, patientID: id, patientName: name)
}
