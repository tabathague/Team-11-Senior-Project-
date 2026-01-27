**Feeding Rate Detection System Using Neural Networks**

Overview

This project implements an automated feeding rate detection system using a camera and a neural network–based digit recognition model. Instead of relying solely on Optical Character Recognition (OCR), the system captures images, preprocesses them, and uses a trained neural network to accurately identify numerical feeding rate values displayed on a device.

The system is designed to be modular, allowing for easy upgrades to the camera, image processing pipeline, or neural network model.

**System Workflow**

_Image Capture_

A camera is used to capture images of the feeding rate display.

Images are saved locally for processing and logging.

_Image Preprocessing_

Captured images are converted to grayscale.

Noise reduction and thresholding are applied to improve digit visibility.

The region of interest containing the digits is isolated and resized.

_Neural Network Model_

If a pretrained digit recognition model exists, it is loaded.

If not, a new model is trained using a labeled digit dataset.

Images are normalized and formatted before being passed into the model.

_Digit Recognition_

The neural network predicts the digits shown in the image.

Predicted digits are combined to form the full feeding rate value.

_Data Storage_

The recognized feeding rate is saved to a file.

Timestamped logs allow for tracking changes over time.


**Requirements**
change this at some point

**System Workflow**

_Image Capture_

A camera is used to capture images of the feeding rate display.

Images are saved locally for processing and logging.

_Image Preprocessing_

Captured images are converted to grayscale.

Noise reduction and thresholding are applied to improve digit visibility.

The region of interest containing the digits is isolated and resized.

_Neural Network Model_

If a pretrained digit recognition model exists, it is loaded.

If not, a new model is trained using a labeled digit dataset.

Images are normalized and formatted before being passed into the model.

_Digit Recognition_

The neural network predicts the digits shown in the image.

Predicted digits are combined to form the full feeding rate value.

_Data Storage_

The recognized feeding rate is saved to a file.

Timestamped logs allow for tracking changes over time.

**Requirements**

Camera module (USB or compatible device)

Python environment

Image processing library

Neural network library

File saving / data logging utilities
