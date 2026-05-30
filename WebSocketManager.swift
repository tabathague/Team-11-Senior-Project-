//
//  WebSocketManager.swift
//  BiteToByte
//
//  Created by Tabatha Guebard on 5/7/26.
//  WebSocketManager.swift
//  BiteToByte

import Foundation
import Combine
import CoreData

class WebSocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {

    private var webSocketTask: URLSessionWebSocketTask?
    private let url = URL(string: "wss://10.0.0.183:8765")!
    private let context = PersistenceController.shared.container.viewContext
    private var session: URLSession!
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?

    // Volume tracking
    private var lastTimestamp: Date? = nil
    private var currentPeriodVolume: Double = 0.0
    private var currentPeriodStart: Date? = nil
    private var currentPeriodHour: Int = 1
    private var previousPeriodLabel: String? = nil
    private var currentDayLog: DayLog? = nil

    @Published var isConnected: Bool = false
    @Published var latestRate: String = "No data"
    @Published var latestStatus: String = ""

    var patientID: String = ""
    var patientName: String = ""

    override init() {
        super.init()
        session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: OperationQueue()
        )
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func connect(patientID: String, patientName: String) {
        self.patientID = patientID
        self.patientName = patientName

        print("[WS] Attempting to connect to \(url)")
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        receiveMessage()

        let payload = ["patientID": patientID, "patientName": patientName]
        if let json = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: json, encoding: .utf8) {
            sendMessage(jsonString)
            print("[WS] Sent patient ID: \(patientID)")
        }
        
        DispatchQueue.main.async {
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.webSocketTask?.sendPing { error in
                    if let error = error {
                        print("[WS] Ping failed: \(error)")
                        DispatchQueue.main.async { self?.isConnected = false }
                    } else {
                        print("[WS] Ping OK")
                    }
                }
            }
        }
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
    }
    
    private func scheduleReconnect() {
        guard reconnectTimer == nil else { return }
        print("[WS] Reconnecting in 5 seconds...")
        DispatchQueue.main.async {
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.reconnectTimer = nil
                print("[WS] Attempting reconnect...")
                self.connect(patientID: self.patientID, patientName: self.patientName)
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    print("[WS] Received: \(text)")
                    if let jsonData = text.data(using: .utf8) {
                        do {
                            let reading = try JSONDecoder().decode(FlowData.self, from: jsonData)
                            print("[WS] Decoded OK: rate=\(reading.rate) status=\(reading.status)")
                            DispatchQueue.main.async {
                                self?.latestRate = reading.rate
                                self?.latestStatus = reading.status
                                self?.processReading(reading: reading)
                            }
                        } catch {
                            print("[WS] Decode FAILED: \(error)")
                            print("[WS] Raw JSON was: \(text)")
                        }
                    }
                default:
                    break
                }
                self?.receiveMessage()

            case .failure(let error):
                print("[WS] Error: \(error)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.scheduleReconnect()
                }
            }
        }
    }

    func sendMessage(_ message: String) {
        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(wsMessage) { error in
            if let error = error { print("[WS] Send error: \(error)") }
        }
    }

    // MARK: - Main Processing

    func processReading(reading: FlowData) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Truncate microseconds to milliseconds (ISO8601DateFormatter can't handle 6 decimal places)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")

        guard let currentTimestamp = formatter.date(from: reading.timestamp) else {
            print("[DB] Failed to parse timestamp: \(reading.timestamp)")
            return
        }
        print("[DB] Processing reading: rate=\(reading.rate) time=\(currentTimestamp)")

        // Get or create today's DayLog
        let dayDate = Calendar.current.startOfDay(for: Date())
        let request: NSFetchRequest<DayLog> = DayLog.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "date == %@", dayDate as NSDate),
            NSPredicate(format: "id == %@", patientID)
        ])

        let dayLog: DayLog
        if let existing = (try? context.fetch(request))?.first {
            dayLog = existing
        } else {
            dayLog = DayLog(context: context)
            dayLog.id = patientID
            dayLog.name = patientName
            dayLog.date = dayDate
            dayLog.createdAt = Date()
            print("[DB] Created new DayLog for \(dayDate)")
        }
        currentDayLog = dayLog

        if currentPeriodStart == nil {
            currentPeriodStart = currentTimestamp
        }

        if let lastTime = lastTimestamp,
           let rate = Double(reading.rate.components(separatedBy: " ").first ?? "") {
            let hoursElapsed = currentTimestamp.timeIntervalSince(lastTime) / 3600.0
            let volumeIncrement = rate * hoursElapsed
            currentPeriodVolume += volumeIncrement
            print("[VOLUME] +\(String(format: "%.4f", volumeIncrement)) mL | Period total: \(String(format: "%.2f", currentPeriodVolume)) mL")
            updateCurrentPeriod(dayLog: dayLog, currentTime: currentTimestamp)
        }

        if let periodStart = currentPeriodStart {
            let hoursIntoPeriod = currentTimestamp.timeIntervalSince(periodStart) / 3600.0
            if hoursIntoPeriod >= 2.0 {
                finalizePeriod(dayLog: dayLog, endTime: currentTimestamp)
            }
        }

        if Double(reading.rate.components(separatedBy: " ").first ?? "") != nil {
            let entry = EntryLog(context: context)
            entry.id = patientID
            entry.name = patientName
            entry.time = currentTimestamp
            entry.volume = currentPeriodVolume
            entry.day = dayLog
            print("[DB] Saving entry: rate=\(reading.rate) volume=\(currentPeriodVolume) patientID=\(patientID)")
        }

        print("[DB] Saving entry: rate=\(reading.rate) volume=\(currentPeriodVolume) patientID=\(patientID)")
            lastTimestamp = currentTimestamp
            try? context.save()
            deleteExpiredLogs()
    }

    // MARK: - Volume Period Management

    private func updateCurrentPeriod(dayLog: DayLog, currentTime: Date) {
        guard let periodStart = currentPeriodStart else { return }

        let endHour = currentPeriodHour + 1
        let label = "Hours \(currentPeriodHour)-\(endHour)"

        // Find existing live period or create one
        let request: NSFetchRequest<VolumePeriod> = VolumePeriod.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "day == %@", dayLog),
            NSPredicate(format: "periodLabel == %@", label)
        ])

        let period: VolumePeriod
        if let existing = (try? context.fetch(request))?.first {
            period = existing
        } else {
            period = VolumePeriod(context: context)
            period.startTime = periodStart
            period.periodLabel = label
            period.patientID = patientID
            period.setValue(dayLog, forKey: "day")
        }

        period.volume = currentPeriodVolume
        period.endTime = currentTime
        try? context.save()
    }

    private func finalizePeriod(dayLog: DayLog, endTime: Date) {
        let endHour = currentPeriodHour + 1
        let completedLabel = "Hours \(currentPeriodHour)-\(endHour)"

        print("[VOLUME] Period \(completedLabel) complete: \(String(format: "%.2f", currentPeriodVolume)) mL")

        // If there's a period 2 cycles ago, delete it
        if let oldLabel = previousPeriodLabel {
            let deleteRequest: NSFetchRequest<VolumePeriod> = VolumePeriod.fetchRequest()
            deleteRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "day == %@", dayLog.objectID),
                NSPredicate(format: "periodLabel == %@", oldLabel)
            ])
            if let toDelete = try? context.fetch(deleteRequest) {
                toDelete.forEach { context.delete($0) }
                print("[VOLUME] Deleted old period: \(oldLabel)")
            }
        }

        // Store the completed label as previous
        previousPeriodLabel = completedLabel

        // Move to next period
        currentPeriodHour += 2
        currentPeriodStart = endTime
        currentPeriodVolume = 0.0
        lastTimestamp = endTime
    }

    // MARK: - 30 Day Cleanup

    private func deleteExpiredLogs() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let request: NSFetchRequest<DayLog> = DayLog.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "createdAt < %@", cutoff as NSDate),
            NSPredicate(format: "id == %@", patientID)
        ])
        if let expired = try? context.fetch(request) {
            expired.forEach { context.delete($0) }
            try? context.save()
            print("[DB] Deleted \(expired.count) expired day logs")
        }
    }
}
