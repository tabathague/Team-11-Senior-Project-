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
    var body: some Scene {
        WindowGroup {
            PatientSetupView()
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        }
    }
}
