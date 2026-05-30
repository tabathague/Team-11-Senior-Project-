//
//  BiteToByteApp.swift
//  BiteToByte
//
//  Created by Shivani Gunasekar on 2/2/26.
//

import SwiftUI
import CoreData

@main
struct BiteToByteApp: App {
    
    let persistenceController = PersistenceController.shared
    
    init() {
        let context = persistenceController.container.viewContext
        
        let fetchRequest: NSFetchRequest<EntryLog> = EntryLog.fetchRequest()
        
        if let count = try? context.count(for: fetchRequest), count == 0 {
                // Provide a default Test ID so the app has data for you to verify
                importCSVIntoCoreData(context: context, id: "000000", name: "Test")
        }
    }

    var body: some Scene {
        WindowGroup {
            BarcodeScan()
                .environment(\.managedObjectContext,
                              persistenceController.container.viewContext)
        }
    }
}
