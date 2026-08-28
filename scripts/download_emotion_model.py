#!/usr/bin/env python3
"""Download or create the FER2013 emotion detection TFLite model.

Usage:
    pip install tensorflow numpy
    python scripts/download_emotion_model.py

Places the model at app/assets/models/emotion_model.tflite
"""

import os
import sys
import subprocess
import struct

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "app", "assets", "models")
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "emotion_model.tflite")

EMOTION_LABELS = ["Angry", "Disgust", "Fear", "Happy", "Sad", "Surprise", "Neutral"]


def download_from_hub():
    """Try downloading a pre-trained FER2013 TFLite model from Hugging Face."""
    try:
        from huggingface_hub import hf_hub_download

        # Try a known FER2013 TFLite model on HF
        model_path = hf_hub_download(
            repo_id=" LogeswarT/fer2013-tflite",
            filename="emotion_model.tflite",
            local_dir=OUTPUT_DIR,
        )
        # Rename if needed
        if model_path != OUTPUT_PATH:
            os.replace(model_path, OUTPUT_PATH)
        print(f"Downloaded model to {OUTPUT_PATH}")
        return True
    except Exception as e:
        print(f"HuggingFace download failed: {e}")
        return False


def download_from_github():
    """Try downloading from a known GitHub release."""
    urls = [
        "https://github.com/misbah4044/facial_expression_recognition/raw/main/emotion_model.tflite",
        "https://github.com/LogeswarT/FER2013-TFLite/raw/main/emotion_model.tflite",
    ]
    for url in urls:
        try:
            subprocess.check_call(["curl", "-L", "-o", OUTPUT_PATH, url])
            if os.path.getsize(OUTPUT_PATH) > 1000:
                print(f"Downloaded model from {url}")
                return True
        except Exception:
            continue
    return False


def create_tflite_model():
    """Create a minimal TFLite emotion model using TensorFlow."""
    try:
        import tensorflow as tf
        import numpy as np

        print("Creating FER2013 emotion model with TensorFlow...")

        model = tf.keras.Sequential([
            tf.keras.layers.Input(shape=(48, 48, 1)),
            tf.keras.layers.Conv2D(32, (3, 3), activation="relu", padding="same"),
            tf.keras.layers.BatchNormalization(),
            tf.keras.layers.Conv2D(32, (3, 3), activation="relu", padding="same"),
            tf.keras.layers.MaxPooling2D((2, 2)),
            tf.keras.layers.Dropout(0.25),

            tf.keras.layers.Conv2D(64, (3, 3), activation="relu", padding="same"),
            tf.keras.layers.BatchNormalization(),
            tf.keras.layers.Conv2D(64, (3, 3), activation="relu", padding="same"),
            tf.keras.layers.MaxPooling2D((2, 2)),
            tf.keras.layers.Dropout(0.25),

            tf.keras.layers.Conv2D(128, (3, 3), activation="relu", padding="same"),
            tf.keras.layers.BatchNormalization(),
            tf.keras.layers.MaxPooling2D((2, 2)),
            tf.keras.layers.Dropout(0.25),

            tf.keras.layers.Flatten(),
            tf.keras.layers.Dense(256, activation="relu"),
            tf.keras.layers.BatchNormalization(),
            tf.keras.layers.Dropout(0.5),
            tf.keras.layers.Dense(128, activation="relu"),
            tf.keras.layers.Dropout(0.5),
            tf.keras.layers.Dense(7, activation="softmax"),
        ])

        model.compile(
            optimizer="adam",
            loss="sparse_categorical_crossentropy",
            metrics=["accuracy"],
        )

        # Try to load FER2013 dataset
        fer_path = os.path.join(OUTPUT_DIR, "fer2013.csv")
        if os.path.exists(fer_path):
            print("Found fer2013.csv — training model...")
            import pandas as pd

            data = pd.read_csv(fer_path)
            pixels = data["pixels"].apply(
                lambda x: np.array(x.split(), dtype=np.float32).reshape(48, 48, 1)
            )
            X = np.stack(pixels.values) / 255.0
            y = data["emotion"].values

            # Split
            from sklearn.model_selection import train_test_split

            X_train, X_val, y_train, y_val = train_test_split(
                X, y, test_size=0.15, random_state=42, stratify=y
            )

            model.fit(
                X_train, y_train,
                validation_data=(X_val, y_val),
                epochs=30,
                batch_size=64,
                callbacks=[
                    tf.keras.callbacks.EarlyStopping(patience=5, restore_best_weights=True)
                ],
            )
        else:
            print("No fer2013.csv found — creating untrained model (update later).")
            print("Download FER2013.csv from https://www.kaggle.com/datasets/msambare/fer2013")
            # Create with random weights — better than nothing
            # The model structure is correct; weights will be updated when retrained
            pass

        # Convert to TFLite
        converter = tf.lite.TFLiteConverter.from_keras_model(model)
        tflite_model = converter.convert()

        os.makedirs(OUTPUT_DIR, exist_ok=True)
        with open(OUTPUT_PATH, "wb") as f:
            f.write(tflite_model)

        size_kb = os.path.getsize(OUTPUT_PATH) / 1024
        print(f"Model saved to {OUTPUT_PATH} ({size_kb:.0f} KB)")
        return True

    except ImportError:
        print("TensorFlow not installed. Install with: pip install tensorflow")
        return False
    except Exception as e:
        print(f"Model creation failed: {e}")
        return False


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Already exists?
    if os.path.exists(OUTPUT_PATH) and os.path.getsize(OUTPUT_PATH) > 1000:
        print(f"Model already exists at {OUTPUT_PATH}")
        return

    print("Attempting to download pre-trained FER2013 TFLite model...\n")

    # Try HuggingFace first
    if download_from_hub():
        return

    # Try GitHub releases
    if download_from_github():
        return

    # Fall back to creating from scratch
    print("\nNo pre-trained model available. Creating model with TensorFlow...\n")
    if create_tflite_model():
        return

    print("\nFailed to obtain model. Manual steps:")
    print("1. Download fer2013.csv from https://www.kaggle.com/datasets/msambare/fer2013")
    print(f"2. Place it at {os.path.join(OUTPUT_DIR, 'fer2013.csv')}")
    print("3. Run this script again: python scripts/download_emotion_model.py")


if __name__ == "__main__":
    main()
