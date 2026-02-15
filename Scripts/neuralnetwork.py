# imports and configuration
import cv2
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models
from datetime import datetime
import sqlite3
import os
from collections import deque

MODEL_PATH = "digit_model.h5"
DB_PATH = "feeding_rates.db"
CAMERA_INDEX = 0

IMG_SIZE = 28
CONFIDENCE_THRESHOLD = 0.90
CONSISTENT_FRAMES_REQUIRED = 3

# CNN digit model
def build_digit_model(input_shape=(28,28,1)):
    model = models.Sequential([
        layers.Conv2D(32, (3,3), activation="relu", input_shape=input_shape),
        layers.MaxPooling2D((2,2)),

        layers.Conv2D(64, (3,3), activation="relu"),
        layers.MaxPooling2D((2,2)),

        layers.Flatten(),
        layers.Dense(128, activation="relu"),
        layers.Dense(10, activation="softmax")
    ])

    model.compile(
        optimizer="adam",
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"]
    )
    return model

# load model
def load_or_train_model():
    if os.path.exists(MODEL_PATH):
        return tf.keras.models.load_model(MODEL_PATH)

    raise RuntimeError(
        "digit_model.h5 not found — train using real pump digits first"
    )

# Database
def init_database():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS feeding_rate (
            timestamp TEXT,
            rate INTEGER,
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
        (datetime.utcnow().isoformat(), rate, confidence, raw_digits)
    )
    conn.commit()

# Fixed Screen ROI
def detect_screen_region(frame):
    # Calibrate ONCE for your setup
    x1, y1, x2, y2 = 300, 200, 700, 400
    return frame[y1:y2, x1:x2]

DIGIT_BOXES = [
    (10, 20, 50, 80),
    (70, 20, 50, 80),
    (130, 20, 50, 80)
]

def segment_digits(screen):
    gray = cv2.cvtColor(screen, cv2.COLOR_BGR2GRAY)
    digits = []

    for (x,y,w,h) in DIGIT_BOXES:
        roi = gray[y:y+h, x:x+w]
        roi = cv2.resize(roi, (IMG_SIZE, IMG_SIZE))
        roi = roi.astype("float32") / 255.0
        roi = roi.reshape(IMG_SIZE, IMG_SIZE, 1)
        digits.append(roi)

    return digits

def predict_rate(model, digit_images):
    digits = []
    confidences = []

    for img in digit_images:
        probs = model.predict(img[np.newaxis, ...], verbose=0)[0]
        digits.append(str(np.argmax(probs)))
        confidences.append(float(np.max(probs)))

    rate = int("".join(digits))
    confidence = min(confidences)

    return rate, confidence, "".join(digits)

rate_buffer = deque(maxlen=CONSISTENT_FRAMES_REQUIRED)

def is_stable(rate):
    rate_buffer.append(rate)
    return len(rate_buffer) == rate_buffer.maxlen and len(set(rate_buffer)) == 1

def main():
    model = load_or_train_model()
    conn = init_database()

    cap = cv2.VideoCapture(CAMERA_INDEX)
    print("[INFO] Camera started")

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        screen = detect_screen_region(frame)
        digit_images = segment_digits(screen)

        rate, confidence, raw_digits = predict_rate(model, digit_images)

        if confidence >= CONFIDENCE_THRESHOLD and is_stable(rate):
            print(f"[CLINICAL] {rate} mL/hr (conf={confidence:.2f})")
            save_rate(conn, rate, confidence, raw_digits)
            rate_buffer.clear()
        else:
            print(f"[ML] {rate} (conf={confidence:.2f})")

        cv2.imshow("Pump Screen", screen)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    conn.close()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()

