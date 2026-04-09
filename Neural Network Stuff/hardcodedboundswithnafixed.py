# ==========================================
# FULL PIPELINE:
# 1. FEEDING DETECTION
# 2. IF FEEDING → DIGIT RECOGNITION
# ==========================================

import cv2
import sqlite3
import numpy as np
import tensorflow as tf
from datetime import datetime

# -----------------------------
# CONFIG
# -----------------------------

# Models
FEEDING_MODEL_PATH = "feeding_model.h5"
DIGIT_MODEL_PATH = "digit_model.h5"

# Image to test
IMAGE_PATH = "Test images/259test.png"

# Feeding model config
IMG_SIZE_FEEDING = 128
CLASS_NAMES = ["feeding", "not_feeding"]

# Digit model config
IMG_SIZE_DIGIT = 28
CONFIDENCE_THRESHOLD = 0.80
NONE_CLASS_INDEX = 10

# Database
DB_PATH = "feeding_rates.db"

# Screen + digit regions
SCREEN_BOUNDS = (282, 655, 1649, 1424)

DIGIT_BOXES = [
    (488, 115, 192, 171),
    (627, 82, 165, 213),
    (735, 62, 156, 226)
]

# -----------------------------
# LOAD MODELS
# -----------------------------

print("[INFO] Loading models...")
feeding_model = tf.keras.models.load_model(FEEDING_MODEL_PATH)
digit_model = tf.keras.models.load_model(DIGIT_MODEL_PATH)


# -----------------------------
# DATABASE
# -----------------------------

def init_database():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS feeding_rate (
            timestamp TEXT,
            rate TEXT,
            confidence REAL,
            raw_digits TEXT
        )
    """)
    conn.commit()
    return conn


def save_rate(conn, rate, confidence, raw_digits):
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO feeding_rate VALUES (?, ?, ?, ?)",
        (datetime.utcnow().isoformat(), str(rate), confidence, raw_digits)
    )
    conn.commit()


# -----------------------------
# STEP 1: FEEDING DETECTION
# -----------------------------

def is_feeding(image_path):
    print(f"\n[STEP 1] Checking feeding status: {image_path}")

    img = tf.keras.utils.load_img(
        image_path,
        color_mode="grayscale",
        target_size=(IMG_SIZE_FEEDING, IMG_SIZE_FEEDING)
    )

    img_array = tf.keras.utils.img_to_array(img) / 255.0
    img_array = np.expand_dims(img_array, axis=0)

    prediction = feeding_model.predict(img_array)[0][0]

    predicted_class = 1 if prediction > 0.5 else 0
    confidence = prediction if prediction > 0.5 else (1 - prediction)

    print(f"[INFO] Prediction: {CLASS_NAMES[predicted_class]} ({confidence:.2f})")

    return predicted_class == 0  # 0 = feeding


# -----------------------------
# STEP 2: DIGIT PIPELINE
# -----------------------------

def detect_screen_region(frame):
    x1, y1, x2, y2 = SCREEN_BOUNDS
    return frame[y1:y2, x1:x2]


def segment_digits(screen):
    gray = cv2.cvtColor(screen, cv2.COLOR_BGR2GRAY)
    digits = []

    for (x, y, w, h) in DIGIT_BOXES:
        roi = gray[y:y+h, x:x+w]
        roi = cv2.resize(roi, (IMG_SIZE_DIGIT, IMG_SIZE_DIGIT))
        roi = roi.astype("float32") / 255.0
        roi = roi.reshape(IMG_SIZE_DIGIT, IMG_SIZE_DIGIT, 1)
        digits.append(roi)

    return digits


def predict_rate(model, digit_images):
    digits = []
    confidences = []
    raw_predictions = []

    for img in digit_images:
        probs = model.predict(img[np.newaxis, ...], verbose=0)[0]
        pred_class = np.argmax(probs)
        conf = float(np.max(probs))

        confidences.append(conf)

        if pred_class == NONE_CLASS_INDEX:
            raw_predictions.append("none")
        else:
            raw_predictions.append(str(pred_class))
            digits.append(str(pred_class))

    if len(digits) == 0:
        return None, min(confidences), "none_none_none"

    rate = int("".join(digits))
    confidence = min(confidences)
    return rate, confidence, "_".join(raw_predictions)


# -----------------------------
# MAIN PIPELINE FUNCTION
# -----------------------------

def process_image(image_path):

    # STEP 1: Check feeding
    if not is_feeding(image_path):
        print("\n[RESULT] ❌ NOT FEEDING — adding entry to database\n")

        # Connect to the database
        conn = init_database()

        # Prepare the data to insert
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        rate = "Not feeding"
        confidence = "NA"
        raw_digits = "NA"

        # Insert the data into the database
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO feeding_rate (timestamp, rate, confidence, raw_digits)
            VALUES (?, ?, ?, ?);
        """, (timestamp, rate, confidence, raw_digits))

        # Commit and close the connection
        conn.commit()
        conn.close()

        print(f"[RESULT] Entry added to database: {timestamp}, {rate}, {confidence}, {raw_digits}")
        return

    print("\n[RESULT] ✅ FEEDING DETECTED — running digit recognition\n")

    conn = init_database()

    frame = cv2.imread(image_path)
    if frame is None:
        print("[ERROR] Could not load image.")
        return

    screen = detect_screen_region(frame)
    digit_images = segment_digits(screen)

    rate, confidence, raw_digits = predict_rate(digit_model, digit_images)

    timestamp = datetime.now().strftime("%H:%M:%S")

    if rate is not None and confidence >= CONFIDENCE_THRESHOLD:
        print(f"[{timestamp}] [CLINICAL] {rate} mL/hr (conf={confidence:.2f})")
        save_rate(conn, rate, confidence, raw_digits)
    else:
        print(f"[{timestamp}] [ML] Invalid/Low confidence → NA")
        save_rate(conn, "NA", confidence, raw_digits)

    conn.close()

    # Debug visualization
    overlay = screen.copy()
    for (x, y, w, h) in DIGIT_BOXES:
        cv2.rectangle(overlay, (x, y), (x+w, y+h), (0,255,0), 2)

    cv2.imshow("Debug - Digit Boxes", overlay)
    cv2.waitKey(0)
    cv2.destroyAllWindows()


# -----------------------------
# RUN
# -----------------------------

if __name__ == "__main__":
    process_image(IMAGE_PATH)