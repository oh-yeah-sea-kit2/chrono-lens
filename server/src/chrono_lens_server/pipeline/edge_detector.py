"""
Phase 3: Canny edge detection for ControlNet conditioning.
"""

import io
import logging

import numpy as np

logger = logging.getLogger(__name__)

CANNY_LOW = 100
CANNY_HIGH = 200


def jpeg_to_canny(jpeg: bytes) -> "PIL.Image.Image":
    """Convert JPEG bytes → Canny edge map as PIL Image (RGB)."""
    import cv2
    from PIL import Image

    buf = np.frombuffer(jpeg, dtype=np.uint8)
    img_bgr = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    img_bgr = cv2.resize(img_bgr, (512, 512))

    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, CANNY_LOW, CANNY_HIGH)

    # ControlNet expects 3-channel image
    edges_rgb = cv2.cvtColor(edges, cv2.COLOR_GRAY2RGB)
    return Image.fromarray(edges_rgb)
