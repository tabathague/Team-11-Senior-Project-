**Feeding Rate Detection System Using Neural Networks**

Overview

This project implements an automated feeding rate detection system using a camera and a neural network–based digit recognition model. Instead of relying solely on Optical Character Recognition (OCR), the system captures images, preprocesses them, and uses a trained neural network to accurately identify numerical feeding rate values displayed on a device.

The system is designed to be modular, allowing for easy upgrades to the camera, image processing pipeline, or neural network model.

**System Workflow**

Image Capture

A camera is used to capture images of the feeding rate display.

Images are saved locally for processing and logging.

Image Preprocessing

Captured images are converted to grayscale.

Noise reduction and thresholding are applied to improve digit visibility.

The region of interest containing the digits is isolated and resized.

Neural Network Model

If a pretrained digit recognition model exists, it is loaded.

If not, a new model is trained using a labeled digit dataset.

Images are normalized and formatted before being passed into the model.

Digit Recognition

The neural network predicts the digits shown in the image.

Predicted digits are combined to form the full feeding rate value.

Data Storage

The recognized feeding rate is saved to a file.

Timestamped logs allow for tracking changes over time.


**Requirements**
change this at some point

**System Workflow**

Image Capture

A camera is used to capture images of the feeding rate display.

Images are saved locally for processing and logging.

Image Preprocessing

Captured images are converted to grayscale.

Noise reduction and thresholding are applied to improve digit visibility.

The region of interest containing the digits is isolated and resized.

Neural Network Model

If a pretrained digit recognition model exists, it is loaded.

If not, a new model is trained using a labeled digit dataset.

Images are normalized and formatted before being passed into the model.

Digit Recognition

The neural network predicts the digits shown in the image.

Predicted digits are combined to form the full feeding rate value.

Data Storage

The recognized feeding rate is saved to a file.

Timestamped logs allow for tracking changes over time.

Pseudocode Summary

Import required libraries for camera input, image processing, neural networks, and file storage.

Load an existing digit recognition model or train a new one if none is available.

Capture an image from the camera.

Preprocess the image to enhance digit recognition.

Use the neural network to detect and classify digits.

Save the extracted feeding rate to a file for later analysis.

**Requirements**

Camera module (USB or compatible device)

Python environment

Image processing library

Neural network library

File saving / data logging utilities

Key Advantages

More robust than traditional OCR for numeric displays

Adaptable to different lighting conditions and display styles

Modular design for easy upgrades and testing

Future Improvements

Expand the training dataset to improve accuracy

Add real-time video processing

Implement confidence scoring for predictions

Integrate cloud storage or a live dashboard
