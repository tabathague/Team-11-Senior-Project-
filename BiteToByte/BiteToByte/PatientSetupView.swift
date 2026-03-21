import SwiftUI
import CoreData

struct PatientSetupView: View {
    let patientName: String = "Jane Doe"
    let patientID: String = "A123456"

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
                    if isConfirmed && feedType != nil {
                        navigateToApp = true
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
                .navigationDestination(isPresented: $navigateToApp) {
                    DailyTableView()
                        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                }
            }
            .padding()
            .navigationTitle("Setup")
        }
    }
}

#Preview {
    PatientSetupView()
}
