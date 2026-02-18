# ==============================
# PUMP FEEDING DETECTION TRAINING SCRIPT
# ==============================
''' 
Dataset directory structure:

Data/
    pump_images/
        feeding/
        not_feeding/
'''

import os
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix

# ------------------------------
# USER CONFIGURATION
# ------------------------------

DATASET_PATH = "Data/pump_images"   # <<< CHANGE THIS TO YOUR DATA PATH
MODEL_SAVE_PATH = "feeding_model.h5"

IMG_SIZE = 128   # Increased size for better feature detection
BATCH_SIZE = 32
EPOCHS = 15

CLASS_NAMES = ["feeding", "not_feeding"]


# ------------------------------
# BUILD MODEL (Binary Classifier)
# ------------------------------

def build_model(input_shape=(IMG_SIZE, IMG_SIZE, 1)):
    model = models.Sequential([
        layers.Conv2D(32, (3,3), activation="relu", input_shape=input_shape),
        layers.MaxPooling2D((2,2)),

        layers.Conv2D(64, (3,3), activation="relu"),
        layers.MaxPooling2D((2,2)),

        layers.Conv2D(128, (3,3), activation="relu"),
        layers.MaxPooling2D((2,2)),

        layers.Flatten(),
        layers.Dense(128, activation="relu"),
        layers.Dropout(0.5),

        # Binary output
        layers.Dense(1, activation="sigmoid")
    ])

    model.compile(
        optimizer="adam",
        loss="binary_crossentropy",
        metrics=["accuracy"]
    )

    return model


# ------------------------------
# LOAD DATASET
# ------------------------------

def load_dataset(path):
    images = []
    labels = []

    for label_index, class_name in enumerate(CLASS_NAMES):
        folder = os.path.join(path, class_name)

        if not os.path.exists(folder):
            print(f"[WARNING] Folder not found: {folder}")
            continue

        for file in os.listdir(folder):
            img_path = os.path.join(folder, file)

            img = tf.keras.utils.load_img(
                img_path,
                color_mode="grayscale",
                target_size=(IMG_SIZE, IMG_SIZE)
            )

            img_array = tf.keras.utils.img_to_array(img)
            img_array = img_array / 255.0

            images.append(img_array)
            labels.append(label_index)

    return np.array(images), np.array(labels)


# ------------------------------
# MAIN TRAINING PIPELINE
# ------------------------------

def main():

    print("\n[INFO] Loading dataset from:", DATASET_PATH)
    X, y = load_dataset(DATASET_PATH)

    print("[INFO] Total samples loaded:", len(X))

    # Train / Validation / Test split
    X_train, X_temp, y_train, y_temp = train_test_split(
        X, y, test_size=0.3, random_state=42, stratify=y
    )

    X_val, X_test, y_val, y_test = train_test_split(
        X_temp, y_temp, test_size=0.5, random_state=42, stratify=y_temp
    )

    print("[INFO] Training samples:", len(X_train))
    print("[INFO] Validation samples:", len(X_val))
    print("[INFO] Test samples:", len(X_test))

    # Build model
    model = build_model()

    print("\n[INFO] Starting training...\n")

    history = model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        verbose=1
    )

    print("\n[INFO] Training complete.\n")

    # ------------------------------
    # TEST EVALUATION
    # ------------------------------

    print("[INFO] Evaluating on test set...\n")

    test_loss, test_acc = model.evaluate(X_test, y_test, verbose=0)

    print("======================================")
    print("TEST ACCURACY:", round(test_acc * 100, 2), "%")
    print("TEST LOSS:", round(test_loss, 4))
    print("======================================\n")

    # Detailed report
    y_pred_probs = model.predict(X_test)
    y_pred = (y_pred_probs > 0.5).astype("int32").flatten()

    print("Classification Report:\n")
    print(classification_report(y_test, y_pred, target_names=CLASS_NAMES))

    print("Confusion Matrix:\n")
    print(confusion_matrix(y_test, y_pred))

    # Save model
    model.save(MODEL_SAVE_PATH)
    print("\n[INFO] Model saved to:", MODEL_SAVE_PATH)


if __name__ == "__main__":
    main()