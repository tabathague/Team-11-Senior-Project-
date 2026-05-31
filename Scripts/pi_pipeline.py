# ==========================================
# RASPBERRY PI 5 PIPELINE (TFLite + CSV + WEBSOCKET)
# USB Camera → Feeding → YOLO Digits → Rate → CSV + Live Stream
# ==========================================

import cv2
import numpy as np
import csv
import os
import time
import json
import websocket
from datetime import datetime
import tflite_runtime.interpreter as tflite

# -----------------------------
# CONFIG
# -----------------------------

FEEDING_MODEL_PATH   = "../feeding_model.tflite"
DIGIT_MODEL_PATH     = "../digit_model.tflite"
YOLO_MODEL_PATH      = "/home/pi/bite_to_byte_nn/best_int8.tflite"

IMG_SIZE_FEEDING     = 128
IMG_SIZE_DIGIT       = 28
CONFIDENCE_THRESHOLD = 0.65
NONE_CLASS_INDEX     = 10

CSV_PATH = None

WS_URL = "wss://localhost:8765"

# -----------------------------
# WEBSOCKET
# -----------------------------

print("[INFO] Connecting to WebSocket server...")
ws = websocket.WebSocket(sslopt={"cert_reqs": 0})
ws.connect(WS_URL)
print("[INFO] WebSocket connected")


def send_ws(rate, confidence, status):
    global ws
    try:
        msg = {
            "timestamp": datetime.utcnow().isoformat(),
            "rate":       rate,
            "confidence": float(np.array(confidence).item()),
            "status":     status,
            "patientID":  patient_id,
        }
        print("[WS SENT]", msg)
        ws.send(json.dumps(msg))
    except Exception as e:
        print("[WS ERROR]", e)
        print("[INFO] Attempting WebSocket reconnect...")
        try:
            ws = websocket.WebSocket(sslopt={"cert_reqs": 0})
            ws.connect(WS_URL)
            ws.send(json.dumps(msg))
            print("[INFO] Reconnected and message resent")
        except Exception as e2:
            print("[WS RECONNECT FAILED]", e2)


# -----------------------------
# CSV
# -----------------------------

def init_csv():
    if not os.path.exists(CSV_PATH):
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "rate", "confidence", "raw_digits"])


def log_csv(rate, confidence, raw_digits):
    with open(CSV_PATH, "a", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([datetime.utcnow().isoformat(), rate, confidence, raw_digits])


# -----------------------------
# TFLite
# -----------------------------

def load_model(path):
    interpreter = tflite.Interpreter(model_path=path)
    interpreter.allocate_tensors()
    return interpreter


def run_model(interpreter, input_data):
    input_details  = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    input_data = input_data.astype(input_details[0]["dtype"])
    interpreter.set_tensor(input_details[0]["index"], input_data)
    interpreter.invoke()
    return [interpreter.get_tensor(o["index"]) for o in output_details]


# -----------------------------
# LOAD MODELS
# -----------------------------

print("[INFO] Loading models...")
feeding_model = load_model(FEEDING_MODEL_PATH)
digit_model   = load_model(DIGIT_MODEL_PATH)
yolo_model    = load_model(YOLO_MODEL_PATH)

yolo_input_details = yolo_model.get_input_details()


# -----------------------------
# CAMERA
# -----------------------------

cap = cv2.VideoCapture("/dev/video0", cv2.CAP_ANY)
cap.set(cv2.CAP_PROP_FRAME_WIDTH,  640)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
cap.set(cv2.CAP_PROP_FPS, 30)

if not cap.isOpened():
    print("[FATAL] Camera failed to open")
    exit()


def get_frame():
    ret, frame = cap.read()
    return frame if ret else None


# -----------------------------
# FEEDING DETECTION
# -----------------------------

def is_feeding(frame):
    img = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    img = cv2.resize(img, (IMG_SIZE_FEEDING, IMG_SIZE_FEEDING))
    img = img.astype("float32") / 255.0
    img = np.expand_dims(img, axis=(0, -1))
    pred = run_model(feeding_model, img)[0][0]
    return pred > 0.5, pred


# -----------------------------
# NMS HELPERS
# -----------------------------

def iou(a, b):
    ix1 = max(a[0], b[0])
    iy1 = max(a[1], b[1])
    ix2 = min(a[2], b[2])
    iy2 = min(a[3], b[3])
    inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[2] - b[0]) * (b[3] - b[1])
    union = area_a + area_b - inter
    return inter / union if union > 0 else 0


def nms(boxes, iou_threshold=0.3):
    if not boxes:
        return []
    boxes = sorted(boxes, key=lambda b: b[4], reverse=True)
    kept = []
    while boxes:
        best = boxes.pop(0)
        kept.append(best)
        boxes = [b for b in boxes if iou(best, b) < iou_threshold]
    return kept


# -----------------------------
# YOLO DIGIT DETECTION
# -----------------------------

def get_digit_boxes(frame):
    H, W, _ = frame.shape

    h, w = yolo_input_details[0]["shape"][1:3]
    img = cv2.resize(frame, (w, h))
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    img = img.astype(np.float32) / 255.0
    img = np.expand_dims(img, axis=0)

    preds = run_model(yolo_model, img)[0][0]  # (5, 8400)

    boxes_raw = preds[:4]
    scores    = preds[4]

    boxes = []

    for i in range(scores.shape[0]):
        confidence = float(scores[i])
        if confidence < 0.25:
            continue

        x_center = float(boxes_raw[0][i])
        y_center = float(boxes_raw[1][i])
        width    = float(boxes_raw[2][i])
        height   = float(boxes_raw[3][i])

        x1 = int((x_center - width  / 2) * W)
        y1 = int((y_center - height / 2) * H)
        x2 = int((x_center + width  / 2) * W)
        y2 = int((y_center + height / 2) * H)

        x1 = max(0, x1)
        y1 = max(0, y1)
        x2 = min(W, x2)
        y2 = min(H, y2)

        if x2 <= x1 or y2 <= y1:
            continue

        boxes.append((x1, y1, x2, y2, confidence))

    boxes = nms(boxes, iou_threshold=0.3)
    boxes.sort(key=lambda b: b[0])

    print(f"[INFO] YOLO found {len(boxes)} digit(s)")

    return [(b[0], b[1], b[2], b[3]) for b in boxes]


# -----------------------------
# DIGIT SEGMENTATION
# -----------------------------

def segment_digits(frame, boxes):
    gray   = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    digits = []
    for (x1, y1, x2, y2) in boxes:
        roi = gray[y1:y2, x1:x2]
        if roi.size == 0:
            continue
        roi = cv2.resize(roi, (IMG_SIZE_DIGIT, IMG_SIZE_DIGIT))
        roi = roi.astype("float32") / 255.0
        roi = np.expand_dims(roi, axis=(0, -1))
        digits.append(roi)
    return digits


# -----------------------------
# PREDICT RATE
# -----------------------------

def predict_rate(digit_images):
    digits      = []
    confidences = []
    raw         = []

    for img in digit_images:
        probs = run_model(digit_model, img)[0]
        pred  = np.argmax(probs)
        conf  = np.max(probs)
        confidences.append(conf)
        if pred == NONE_CLASS_INDEX:
            raw.append("none")
        else:
            digits.append(str(pred))
            raw.append(str(pred))

    if not digits:
        return None, min(confidences) if confidences else 0, "none"

    rate       = int("".join(digits))
    confidence = min(confidences)
    return rate, confidence, "_".join(raw)


# -----------------------------
# PROCESS FRAME
# -----------------------------

def process_frame(frame):
    feeding, conf = is_feeding(frame)

    if not feeding:
        print("[RESULT] ❌ Not feeding")
        log_csv("Not feeding", conf, "NA")
        send_ws("Not feeding", conf, "idle")
        return

    print("[RESULT] ✅ Feeding detected")

    boxes = get_digit_boxes(frame)

    if not boxes:
        print("[WARNING] No digits detected")
        log_csv("No digits", conf, "NA")
        send_ws("No digits", conf, "error")
        return

    digit_images          = segment_digits(frame, boxes[:3])
    rate, confidence, raw = predict_rate(digit_images)

    timestamp = datetime.now().strftime("%H:%M:%S")

    if rate is not None and confidence >= CONFIDENCE_THRESHOLD:
        print(f"[{timestamp}] {rate} mL/hr (conf={confidence:.2f})")
        log_csv(rate, confidence, raw)
        send_ws(rate, confidence, "valid")
    else:
        print(f"[{timestamp}] Invalid reading (conf={confidence:.2f}, raw={raw})")
        log_csv("Invalid", confidence, raw)
        send_ws("Invalid", confidence, "invalid")


# -----------------------------
# MAIN
# -----------------------------

if __name__ == "__main__":

    print("[INFO] Waiting for patient ID from app...")
    patient_id = None
    while patient_id is None:
        try:
            msg  = ws.recv()
            data = json.loads(msg)
            if "patientID" in data:
                patient_id = data["patientID"]
                print(f"[INFO] Patient ID received: {patient_id}")
        except Exception as e:
            print(f"[ERROR] Waiting for patient ID: {e}")
            break

    if patient_id is None:
        print("[ERROR] No patient ID received, exiting.")
        ws.close()
        exit()

    CSV_PATH = f"{patient_id}.csv"
    print(f"[INFO] Logging to {CSV_PATH}")
    init_csv()

    print("[INFO] Starting pipeline...")

    try:
        while True:
            frame = get_frame()
            if frame is None:
                print("[ERROR] No camera frame")
                continue
            process_frame(frame)
            time.sleep(10)
    finally:
        cap.release()
        ws.close()
