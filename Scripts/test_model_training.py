# ==============================
# DIGIT MODEL TRAINING SCRIPT
# ==============================
''' For training data set, directory should be strucutured as follows
Data/
    digit_images/
        >0
        >1
        >2
        >3
        >4
        >5
        >6
        >7
        >8
        >9
Where each digit folder contains images of corresponding digit'''

import os
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix

# ------------------------------
# USER CONFIGURATION
# ------------------------------

DATASET_PATH = "Data/digit_images"   # <<< CHANGE THIS TO YOUR DATA PATH
MODEL_SAVE_PATH = "digit_model.h5"

IMG_SIZE = 28
BATCH_SIZE = 32
EPOCHS = 15

# ------------------------------
# BUILD MODEL (same as inference)
# ------------------------------

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


# ------------------------------
# LOAD DATASET
# ------------------------------

def load_dataset(path):
    images = []
    labels = []

    for label in range(10):
        folder = os.path.join(path, str(label))

        if not os.path.exists(folder):
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
            labels.append(label)

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
    model = build_digit_model()

    print("\n[INFO] Starting training...\n")

    history = model.fit(
        X_train, y_train,
        validation_data=(X_val, y_val),
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        verbose=1   # prints training progress
    )

    print("\n[INFO] Training complete.\n")

    # ------------------------------
    # VERIFICATION (TEST SET)
    # ------------------------------

    print("[INFO] Evaluating on test set...\n")

    test_loss, test_acc = model.evaluate(X_test, y_test, verbose=0)

    print("======================================")
    print("TEST ACCURACY:", round(test_acc * 100, 2), "%")
    print("TEST LOSS:", round(test_loss, 4))
    print("======================================\n")

    # Detailed report
    y_pred_probs = model.predict(X_test)
    y_pred = np.argmax(y_pred_probs, axis=1)

    print("Classification Report:\n")
    print(classification_report(y_test, y_pred))

    print("Confusion Matrix:\n")
    print(confusion_matrix(y_test, y_pred))

    # Save model
    model.save(MODEL_SAVE_PATH)
    print("\n[INFO] Model saved to:", MODEL_SAVE_PATH)


if __name__ == "__main__":
    main()
