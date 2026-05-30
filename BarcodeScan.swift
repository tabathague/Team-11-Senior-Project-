//
//  BarcodeScan.swift
//  BiteToByte
//
//  Created by Elizabeth Merten on 3/31/26.
//
import SwiftUI
import CoreData
import UIKit
import AVFoundation

struct Patient: Identifiable {
    let id: String
    let name: String
}

func parsePatient(from barcode: String) -> Patient {
    let components = barcode
        .split(separator: ";")
        .map { $0.trimmingCharacters(in: .whitespaces) }

    var name = "Unknown"
    var id = "N/A"

    for item in components {
        let upper = item.uppercased()
        if upper.hasPrefix("NAME=") {
            name = String(item.split(separator: "=", maxSplits: 1)[1])
        } else if upper.hasPrefix("ID=") {
            id = String(item.split(separator: "=", maxSplits: 1)[1])
        }
    }

    return Patient(id: id, name: name)
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}
}

final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onScan: ((String) -> Void)?
    private let session = AVCaptureSession()

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)

        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.code128, .ean13, .ean8, .qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.addSublayer(preview)

        session.startRunning()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        print("Objects detected:", metadataObjects.count)
        
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue else { return }

        print("SCANNED:", code)
        
        session.stopRunning()
        onScan?(code)
    }
}

struct BarcodeScan: View {
    @State private var showScanner = false
    @State private var scannedPatient: Patient? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {

                // Auto-navigate when a patient is scanned
                if let patient = scannedPatient {
                    NavigationLink(
                        destination: PatientSetupView(
                            patientName: patient.name,
                            patientID: patient.id
                        ),
                        isActive: .constant(true)
                    ) {
                        EmptyView()
                    }
                }

                Button("Scan Patient Barcode") {
                    // Reset previous scan
                    scannedPatient = nil
                    showScanner = true
                }
                .font(.title2)
            }
            .navigationTitle("Patient Intake")
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView { barcode in
                    // 1. Parse the string into a Patient object
                    let patient = parsePatient(from: barcode)
                    
                    // 2. Update the state so the NavigationLink triggers
                    self.scannedPatient = patient
                    
                    // 3. Close the scanner
                    self.showScanner = false
                    
                    // 4. (Optional) Print to console for verification
                    print("Successfully scanned ID: \(patient.id)")
                }
            }
        }
    }
}
