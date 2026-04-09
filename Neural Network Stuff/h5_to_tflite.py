###Script converts .h5 model to .tflite model which is more compatible with the Raspberry Pi 5

import tensorflow as tf

# Load your CNN model
model = tf.keras.models.load_model("feeding_model.h5") #ensure this line has the correct input model

# Create converter
converter = tf.lite.TFLiteConverter.from_keras_model(model)

# Optimization (recommended)
converter.optimizations = [tf.lite.Optimize.DEFAULT]

# Convert
tflite_model = converter.convert()

# Save
with open("feeding_model.tflite", "wb") as f: #also rename the output model to dersiredname.tflite here
    f.write(tflite_model)