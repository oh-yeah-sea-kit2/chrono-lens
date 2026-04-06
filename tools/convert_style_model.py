#!/usr/bin/env python3
"""
Convert Google Magenta Arbitrary Style Transfer model to CoreML.

This script downloads the TF Hub model and converts both networks:
  1. Style Prediction Network: style image → style vector (run once per style)
  2. Style Transfer Network: content image + style vector → stylized image (run per frame)

Usage:
    pip install tensorflow coremltools tensorflow-hub
    python tools/convert_style_model.py

Output:
    tools/output/StylePredictor.mlpackage
    tools/output/StyleTransfer.mlpackage
"""

import os
import shutil

import coremltools as ct
import numpy as np
import tensorflow as tf
import tensorflow_hub as hub

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "output")
MODEL_URL = "https://tfhub.dev/google/magenta/arbitrary-image-stylization-v1-256/2"

STYLE_IMAGE_SIZE = 256
CONTENT_IMAGE_SIZE = 384  # Slightly larger for better quality on phone


def download_model():
    """Load the TF Hub model."""
    print(f"Loading model from {MODEL_URL}...")
    model = hub.load(MODEL_URL)
    print("Model loaded successfully")
    return model


def export_style_predictor(model):
    """
    Extract and convert the style prediction network.
    Input: style image [1, 256, 256, 3] float32 (0-1)
    Output: style bottleneck vector [1, 1, 1, 100]
    """
    print("\n--- Converting Style Predictor ---")

    @tf.function(input_signature=[
        tf.TensorSpec(shape=[1, STYLE_IMAGE_SIZE, STYLE_IMAGE_SIZE, 3], dtype=tf.float32)
    ])
    def predict_style(style_image):
        return model.call(
            tf.zeros([1, CONTENT_IMAGE_SIZE, CONTENT_IMAGE_SIZE, 3]),
            style_image,
        )[1]  # [1] is the style bottleneck

    concrete = predict_style.get_concrete_function()

    mlmodel = ct.convert(
        concrete,
        inputs=[ct.ImageType(
            name="style_image",
            shape=(1, STYLE_IMAGE_SIZE, STYLE_IMAGE_SIZE, 3),
            scale=1.0 / 255.0,
            color_layout="RGB",
        )],
        outputs=[ct.TensorType(name="style_vector")],
        minimum_deployment_target=ct.target.iOS16,
    )

    out_path = os.path.join(OUTPUT_DIR, "StylePredictor.mlpackage")
    if os.path.exists(out_path):
        shutil.rmtree(out_path)
    mlmodel.save(out_path)
    print(f"Saved: {out_path}")
    return out_path


def export_style_transfer(model):
    """
    Extract and convert the style transfer network.
    Input: content image [1, H, W, 3] float32 (0-1) + style vector [1, 1, 1, 100]
    Output: stylized image [1, H, W, 3] float32 (0-1)
    """
    print("\n--- Converting Style Transfer Network ---")

    @tf.function(input_signature=[
        tf.TensorSpec(shape=[1, CONTENT_IMAGE_SIZE, CONTENT_IMAGE_SIZE, 3], dtype=tf.float32),
        tf.TensorSpec(shape=[1, 1, 1, 100], dtype=tf.float32),
    ])
    def transfer_style(content_image, style_vector):
        # The model's __call__ accepts (content, style_image) but we can also
        # call the internal transfer with a pre-computed style vector.
        # For the hub model v2, we use the signature that accepts bottleneck directly.
        stylized = model.signatures["serving_default"](
            tf.constant(content_image),
            tf.constant(style_vector),
        )
        # Output key varies; try common ones
        for key in ["output_0", "stylized_image"]:
            if key in stylized:
                return stylized[key]
        return list(stylized.values())[0]

    # Fallback: use the simpler approach with the callable model
    @tf.function(input_signature=[
        tf.TensorSpec(shape=[1, CONTENT_IMAGE_SIZE, CONTENT_IMAGE_SIZE, 3], dtype=tf.float32),
        tf.TensorSpec(shape=[1, STYLE_IMAGE_SIZE, STYLE_IMAGE_SIZE, 3], dtype=tf.float32),
    ])
    def transfer_full(content_image, style_image):
        return model(content_image, style_image)[0]

    try:
        concrete = transfer_style.get_concrete_function()
        input_specs = [
            ct.ImageType(
                name="content_image",
                shape=(1, CONTENT_IMAGE_SIZE, CONTENT_IMAGE_SIZE, 3),
                scale=1.0 / 255.0,
                color_layout="RGB",
            ),
            ct.TensorType(name="style_vector", shape=(1, 1, 1, 100)),
        ]
    except Exception as e:
        print(f"Style vector approach failed ({e}), falling back to full model...")
        concrete = transfer_full.get_concrete_function()
        input_specs = [
            ct.ImageType(
                name="content_image",
                shape=(1, CONTENT_IMAGE_SIZE, CONTENT_IMAGE_SIZE, 3),
                scale=1.0 / 255.0,
                color_layout="RGB",
            ),
            ct.ImageType(
                name="style_image",
                shape=(1, STYLE_IMAGE_SIZE, STYLE_IMAGE_SIZE, 3),
                scale=1.0 / 255.0,
                color_layout="RGB",
            ),
        ]

    mlmodel = ct.convert(
        concrete,
        inputs=input_specs,
        outputs=[ct.ImageType(name="stylized_image", color_layout="RGB")],
        minimum_deployment_target=ct.target.iOS16,
    )

    out_path = os.path.join(OUTPUT_DIR, "StyleTransfer.mlpackage")
    if os.path.exists(out_path):
        shutil.rmtree(out_path)
    mlmodel.save(out_path)
    print(f"Saved: {out_path}")
    return out_path


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    model = download_model()
    export_style_predictor(model)
    export_style_transfer(model)
    print("\n✓ Conversion complete!")
    print(f"  Copy .mlpackage files from {OUTPUT_DIR}/ to mobile/ios/Runner/Models/")


if __name__ == "__main__":
    main()
