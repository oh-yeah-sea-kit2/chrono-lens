#!/usr/bin/env python3
"""
Convert Google Magenta Arbitrary Style Transfer model to CoreML.

The TF Hub model takes (content_image, style_image) and returns [stylized_image].
We convert it as a single combined model (no separate style predictor).

Usage:
    pip install tensorflow coremltools tensorflow-hub setuptools
    python tools/convert_style_model.py

Output:
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

CONTENT_SIZE = 384
STYLE_SIZE = 256


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"Loading model from {MODEL_URL}...")
    hub_model = hub.load(MODEL_URL)
    print("Model loaded successfully")
    print(f"  Signatures: {list(hub_model.signatures.keys()) if hasattr(hub_model, 'signatures') else 'N/A'}")

    # Wrap the model call in a tf.function with explicit input signatures
    @tf.function(input_signature=[
        tf.TensorSpec(shape=[1, CONTENT_SIZE, CONTENT_SIZE, 3], dtype=tf.float32),
        tf.TensorSpec(shape=[1, STYLE_SIZE, STYLE_SIZE, 3], dtype=tf.float32),
    ])
    def stylize(content_image, style_image):
        # hub_model(content, style) returns [stylized_image]
        return hub_model(content_image, style_image)[0]

    print("\nTracing tf.function...")
    concrete = stylize.get_concrete_function()
    print("  Traced successfully")

    # Verify with dummy data
    print("Testing with dummy data...")
    dummy_content = np.random.rand(1, CONTENT_SIZE, CONTENT_SIZE, 3).astype(np.float32)
    dummy_style = np.random.rand(1, STYLE_SIZE, STYLE_SIZE, 3).astype(np.float32)
    result = stylize(tf.constant(dummy_content), tf.constant(dummy_style))
    print(f"  Output shape: {result.shape}, range: [{result.numpy().min():.3f}, {result.numpy().max():.3f}]")

    # Save as SavedModel first (coremltools needs this format)
    saved_model_dir = os.path.join(OUTPUT_DIR, "saved_model_tmp")
    if os.path.exists(saved_model_dir):
        shutil.rmtree(saved_model_dir)

    print("\nExporting to SavedModel...")

    class StylizeModule(tf.Module):
        def __init__(self, hub_model):
            super().__init__()
            self.hub_model = hub_model

        @tf.function(input_signature=[
            tf.TensorSpec(shape=[1, CONTENT_SIZE, CONTENT_SIZE, 3], dtype=tf.float32),
            tf.TensorSpec(shape=[1, STYLE_SIZE, STYLE_SIZE, 3], dtype=tf.float32),
        ])
        def __call__(self, content_image, style_image):
            return self.hub_model(content_image, style_image)[0]

    module = StylizeModule(hub_model)
    tf.saved_model.save(module, saved_model_dir)
    print(f"  Saved to {saved_model_dir}")

    # Convert to CoreML
    print("\nConverting to CoreML...")
    mlmodel = ct.convert(
        saved_model_dir,
        source="tensorflow",
        inputs=[
            ct.ImageType(
                name="content_image",
                shape=(1, CONTENT_SIZE, CONTENT_SIZE, 3),
                scale=1.0 / 255.0,
                color_layout="RGB",
            ),
            ct.ImageType(
                name="style_image",
                shape=(1, STYLE_SIZE, STYLE_SIZE, 3),
                scale=1.0 / 255.0,
                color_layout="RGB",
            ),
        ],
        minimum_deployment_target=ct.target.iOS16,
    )

    # Clean up temp SavedModel
    shutil.rmtree(saved_model_dir)

    out_path = os.path.join(OUTPUT_DIR, "StyleTransfer.mlpackage")
    if os.path.exists(out_path):
        shutil.rmtree(out_path)
    mlmodel.save(out_path)
    print(f"\nSaved: {out_path}")

    # Print model info
    spec = mlmodel.get_spec()
    print(f"  Inputs:  {[i.name for i in spec.description.input]}")
    print(f"  Outputs: {[o.name for o in spec.description.output]}")

    print("\n✓ Conversion complete!")
    print(f"  Copy {out_path} to mobile/ios/Runner/Models/")


if __name__ == "__main__":
    main()
