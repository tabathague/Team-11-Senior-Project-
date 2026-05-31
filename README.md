# Bite to Byte — Enteral Feeding Monitor

A real-time enteral feeding rate monitor that uses machine learning and a native iOS app to track and log IV pump flow for integration to the EMR.

---

## System Overview

Bite to Byte is a full-stack clinical monitoring system consisting of three integrated layers:

1. **Edge Vision Pipeline** — Raspberry Pi camera system that classifies whether a pump is actively feeding and reads the displayed flow rate using a multi-model ML pipeline
2. **WebSocket Server** — A secure relay server running on the Pi that bridges the vision pipeline to the iOS app in real time
3. **iOS App (SwiftUI)** — Patient-facing interface that scans barcodes, configures sessions, receives live telemetry, integrates fluid volumes, and persists data to Core Data with HIPAA-aligned retention policies

---

## Repository Structure

```
.
├── ML Training
│   ├── digitandnoneNN.py        # CNN trainer: digit recognition (0–9 + "none" class)
│   ├── feeding_NN_train.py      # CNN trainer: feeding vs. not-feeding binary classifier
│   └── h5_to_tflite.py          # Converts Keras .h5 models to quantized TFLite for Pi deployment
│
├── Raspberry Pi
│   ├── pi_pipeline.py           # Main vision pipeline: camera capture, model inference, WebSocket stream
│   └── ws_server.py             # Async secure WebSocket server (wss://, TLS)
│
└── iOS App (BiteToByteApp)
    ├── BiteToByteApp.swift       # App entry point; seeds Core Data if empty
    ├── BarcodeScan.swift         # AVFoundation barcode scanner + patient data parser
    ├── PatientSetupView.swift    # Session configuration UI (feed type, clip type, start recording)
    ├── ContentView.swift         # Daily log table view with live data rendering
    ├── CSVImporter.swift         # Parses historical CSV data; trapezoidal volume integration
    ├── FlowData.swift            # Codable DTO for WebSocket sensor payloads
    └── WebSocketManager.swift   # WebSocket client; real-time fluid math engine; Core Data persistence
```

---

## Machine Learning Models

### `digitandnoneNN.py` — Digit Classifier (11-Class CNN)

Trains a convolutional neural network to recognize digits 0–9 and a "none" class (for frames with no visible digit) from 28×28 grayscale images.

**Architecture:** `Conv2D(32) → Pool → Conv2D(64) → Pool → Flatten → Dense(128) → Softmax(11)`

**Dataset layout:**
```
Data/digit_images/
    0/   1/   2/   3/   4/   5/   6/   7/   8/   9/   none/
```

**Output:** `digit_model.h5`

| Parameter | Value |
|-----------|-------|
| Image size | 28×28 px grayscale |
| Classes | 11 (digits 0–9 + none) |
| Epochs | 15 |
| Batch size | 32 |
| Split | 70% train / 15% val / 15% test |

---

### `feeding_NN_train.py` — Feeding State Classifier (Binary CNN)

Trains a binary classifier to determine whether the pump is currently in a feeding state from 128×128 grayscale images.

**Architecture:** `Conv2D(32) → Pool → Conv2D(64) → Pool → Conv2D(128) → Pool → Flatten → Dense(128) → Dropout(0.5) → Sigmoid(1)`

**Dataset layout:**
```
Data/pump_images/
    feeding/
    not_feeding/
```

**Output:** `feeding_model.h5`

| Parameter | Value |
|-----------|-------|
| Image size | 128×128 px grayscale |
| Classes | 2 (feeding / not_feeding) |
| Epochs | 15 |
| Batch size | 32 |
| Loss | Binary cross-entropy |

---

### `h5_to_tflite.py` — Model Converter

Converts a trained Keras `.h5` model to a quantized `.tflite` file for efficient inference on the Raspberry Pi.

```bash
# Edit the input/output filenames inside the script, then run:
python h5_to_tflite.py
```

Applies `tf.lite.Optimize.DEFAULT` (dynamic range quantization) to reduce model size and improve inference speed on ARM hardware.

---

## Raspberry Pi Pipeline

### `ws_server.py` — Secure WebSocket Relay Server

An async Python WebSocket server (`websockets` + `asyncio`) that:
- Listens on `wss://0.0.0.0:8765` (TLS via `cert.pem` / `key.pem`)
- Accepts connections from both the Pi pipeline and the iOS app
- Routes patient ID registration frames from the app → pipeline
- Forwards sensor telemetry frames from the pipeline → app
- Handles client connect/disconnect gracefully

**Prerequisites:**
```bash
pip install websockets
# Generate a self-signed cert for local dev:
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes
```

---

### `pi_pipeline.py` — Vision & Telemetry Pipeline

The main processing loop running on the Raspberry Pi. Executes every 10 seconds:

1. **Capture** a frame from the USB camera (`/dev/video0`)
2. **Classify** feeding state using `feeding_model.tflite`
3. If feeding: run **YOLOv8 digit detection** (`best_int8.tflite`) to locate digit bounding boxes
4. **Segment and classify** each digit using `digit_model.tflite`
5. **Assemble** the flow rate reading from the ordered digit sequence
6. **Log** the result to a patient-specific CSV file
7. **Transmit** the result over WebSocket to the iOS app

**Model paths (configure at top of file):**
```python
FEEDING_MODEL_PATH = "../feeding_model.tflite"
DIGIT_MODEL_PATH   = "../digit_model.tflite"
YOLO_MODEL_PATH    = "/home/pi/bite_to_byte_nn/best_int8.tflite"
```

**Confidence threshold:** Readings below `0.65` confidence are logged as `"Invalid"` and not used for volume calculations.

**Non-maximum suppression (NMS):** Applied to YOLO detections with IoU threshold `0.3` to remove overlapping bounding boxes before digit classification.

**Dependencies:**
```bash
pip install opencv-python numpy tflite-runtime websocket-client
```

---

## iOS App

### Patient Flow

```
Barcode Scan → Patient Setup → Daily Log View (live data)
```

**`BarcodeScan.swift`**
Bridges AVFoundation to SwiftUI to scan patient wristband barcodes. Parses a semicolon-delimited payload format:
```
NAME=Jane Doe; ID=123456
```

**`PatientSetupView.swift`**
Collects session configuration (feed type: Continuous/Bolus; clip type: Feed/Flush), registers or looks up the patient in Core Data, seeds historical CSV data, and opens navigation to the live log view.

**`ContentView.swift`**
Displays a scrollable daily log table of timestamped entries. Includes a test button to simulate a live WebSocket data byte for development/debugging.

---

### Data Layer

**`FlowData.swift`**
A `Codable` Swift struct representing a single telemetry frame received over WebSocket:
```json
{ "timestamp": "2025-01-01T12:00:00.000000", "rate": 45, "status": "valid" }
```
Handles both integer and string-encoded rate values from variable hardware firmware.

**`CSVImporter.swift`**
Parses historical pump log CSVs and writes them to Core Data using **trapezoidal integration** to compute cumulative volume:

```
ΔVolume = FlowRate(t-1) × ΔTime (hours)
```

Resets cumulative volume at day boundaries. Safely skips rows where the rate contains `"none"`, `"not"`, `"invalid"`, or `"na"` (machine vision artifact guard).

**`WebSocketManager.swift`**
An `ObservableObject` managing the live WSS connection from the app to the Pi server. Key responsibilities:

- **SSL bypass** for self-signed local development certificates
- **Heartbeat ping** every 5 seconds to prevent connection timeout
- **Auto-reconnect** loop on disconnect (5-second delay)
- **Real-time trapezoidal integration** of incoming flow rate readings into cumulative mL volumes
- **2-hour rolling window** tracking with `VolumePeriod` Core Data entities; older windows are pruned from memory
- **HIPAA-aligned 30-day retention**: automatically deletes `DayLog` records older than 30 days for the active patient

---

## Core Data Schema

| Entity | Key Fields |
|--------|-----------|
| `PatientProfile` | `id`, `name`, `createdAt` |
| `DayLog` | `id`, `name`, `date`, `createdAt` |
| `EntryLog` | `id`, `name`, `time`, `volume`, `day` (→ DayLog) |
| `VolumePeriod` | `patientID`, `periodLabel`, `startTime`, `endTime`, `volume`, `day` (→ DayLog) |

---

## Local Development Setup

### Raspberry Pi

```bash
# 1. Install Python dependencies
pip install opencv-python numpy tflite-runtime websocket-client

# 2. Generate TLS certificate
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes

# 3. Start the WebSocket server
python ws_server.py

# 4. In a separate terminal, start the vision pipeline
python pi_pipeline.py
```

### ML Training

```bash
pip install tensorflow scikit-learn numpy

# Train digit classifier
python digitandnoneNN.py

# Train feeding classifier
python feeding_NN_train.py

# Convert to TFLite
python h5_to_tflite.py
```

### iOS App

Open the project in Xcode. Ensure the WebSocket target URL in `WebSocketManager.swift` matches your Pi's local IP:
```swift
let targetHardwareURL = URL("wss://10.0.0.183:8765")
```
Build and run on a physical device (AVFoundation barcode scanning requires a real camera).

---

## Notes

- The iOS app uses a self-signed certificate bypass for local network connections. Replace with a properly signed certificate for any production or clinical deployment.
- Patient CSV files are named `{patientID}.csv` and written to the working directory of `pi_pipeline.py`.
- The pipeline waits to receive a `patientID` registration frame from the app before beginning inference and logging.
