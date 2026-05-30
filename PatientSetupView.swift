import SwiftUI
import CoreData

struct PatientSetupView: View {
    let patientName: String
    let patientID: String

    @State private var clipType: ClipType? = nil
    @State private var feedType: FeedType? = nil
    @State private var isConfirmed = false
    @State private var navigateToApp = false

    enum FeedType: String {
        case continuous = "Continuous"
        case bolus = "Bolus"
    }

    enum ClipType: String {
        case feed = "Feed"
        case flush = "Flush"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                var startButtonColor: Color {
                    if isConfirmed && feedType != nil {
                        return .red
                    } else {
                        return .gray
                    }
                }
                // Patient Info
                VStack(spacing: 8){
                    Text("Patient Name")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(patientName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Patient ID")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(patientID)
                        .font(.headline)
                }

                // Confirm Button
                Button(action: {
                    isConfirmed = true
                })  {
                    Text(isConfirmed ? "Confirmed" : "Confirm")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isConfirmed ? Color.green : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                // Feed Type Question
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Feed Type")
                        .font(.headline)

                    HStack(spacing: 16) {
                        Button(action: {
                            feedType = .continuous
                        }) {
                            Text("Continuous")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(feedType == .continuous ? Color.blue : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }

                        Button(action: {
                            feedType = .bolus
                        }) {
                            Text("Bolus")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(feedType == .bolus ? Color.blue : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }

                // Clip Color Question
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Clip Type")
                        .font(.headline)

                    HStack(spacing: 16) {
                        Button(action: {
                            clipType = .feed
                        }) {
                            Text("Feed")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(clipType == .feed ? Color.green : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }

                        Button(action: {
                            clipType = .flush
                        }) {
                            Text("Flush")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(clipType == .flush ? Color.blue : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }

                Spacer()

                // Start Recording Button -> navigates to DailyTableView
                Button {
                    print("DEBUG: Start Recording clicked. Current ID is: '\(patientID)'")
                    if isConfirmed && feedType != nil {
                            let context = PersistenceController.shared.container.viewContext
                            
                            // 1. Check if patient already exists
                            let request: NSFetchRequest<PatientProfile> = PatientProfile.fetchRequest()
                            request.predicate = NSPredicate(format: "id == %@", patientID)
                            
                            do {
                                let results = try context.fetch(request)
                                
                                if results.isEmpty {
                                    // CASE: NEW PATIENT
                                    // Save profile and import their specific CSV (e.g., 230973.csv)
                                    savePatient(name: patientName, id: patientID, context: context)
                                    //importCSVIntoCoreData(context: context, id: patientID, name: patientName)
                                    let cleanID = patientID.trimmingCharacters(in: .whitespacesAndNewlines)

                                    importCSVIntoCoreData(
                                        context: context,
                                        id: cleanID,
                                        name: patientName
                                    )
                                    print("New patient created and CSV imported.")
                                } else {
                                    // CASE: EXISTING PATIENT
                                    // Do nothing here—Core Data already has their data
                                    print("Existing patient found. Loading history.")
                                    //importCSVIntoCoreData(context: context, id: patientID, name: patientName)
                                    let cleanID = patientID.trimmingCharacters(in: .whitespacesAndNewlines)

                                    importCSVIntoCoreData(
                                        context: context,
                                        id: cleanID,
                                        name: patientName
                                    )
                                }
                                
                                // 2. Trigger Navigation
                                navigateToApp = true
                                
                            } catch {
                                print("Error checking for patient: \(error)")
                            }
                        }
                } label: {
                    Text("Start Recording")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(startButtonColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(!isConfirmed || feedType == nil)
//                .navigationDestination(isPresented: $navigateToApp) {
//                    DailyTableView(id: patientID)
//                        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .navigationDestination(isPresented: $navigateToApp) {
                    DailyTableView(id: patientID, name: patientName)  // add name here
                        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                }
            }
            .padding()
            .navigationTitle("Setup")
        }
    }
}

func savePatient(name: String, id: String, context: NSManagedObjectContext) {
    let patient = PatientProfile(context: context)
    patient.id = id
    patient.name = name
    patient.createdAt = Date()
    
do {
    try context.save()
    print("Patient saved")
    } catch {
        print("Error saving patient:", error)
    }
}

#Preview {
    PatientSetupView(patientName: "", patientID: "")
}
