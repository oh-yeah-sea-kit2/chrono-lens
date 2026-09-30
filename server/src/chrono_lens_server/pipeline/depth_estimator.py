"""
Phase 3 (optional): MiDaS depth estimation for ControlNet Depth conditioning.
Adds ~20-40ms per frame. Use previous frame's depth map to amortize cost.
"""

import io
import logging

import numpy as np

logger = logging.getLogger(__name__)

_midas_model = None
_midas_transform = None
_prev_depth_map = None


def load_midas():
    global _midas_model, _midas_transform
    import torch
    logger.info("Loading MiDaS depth model...")
    _midas_model = torch.hub.load("intel-isl/MiDaS", "MiDaS_small")
    _midas_model.to("cuda").eval()
    transforms = torch.hub.load("intel-isl/MiDaS", "transforms")
    _midas_transform = transforms.small_transform
    logger.info("MiDaS ready")


def jpeg_to_depth(jpeg: bytes) -> "PIL.Image.Image":
    """
    Convert JPEG → depth map as PIL Image (RGB, 512x512).
    Falls back to previous frame's depth map if available.
    """
    global _prev_depth_map
    import cv2
    import torch
    from PIL import Image

    if _midas_model is None:
        load_midas()

    buf = np.frombuffer(jpeg, dtype=np.uint8)
    img_bgr = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)

    input_tensor = _midas_transform(img_rgb).to("cuda")
    with torch.no_grad():
        depth = _midas_model(input_tensor)
        depth = torch.nn.functional.interpolate(
            depth.unsqueeze(1),
            size=(512, 512),
            mode="bicubic",
            align_corners=False,
        ).squeeze()

    depth_np = depth.cpu().numpy()
    depth_norm = ((depth_np - depth_np.min()) / (depth_np.max() - depth_np.min() + 1e-6) * 255).astype(np.uint8)
    depth_rgb = cv2.cvtColor(depth_norm, cv2.COLOR_GRAY2RGB)
    result = Image.fromarray(depth_rgb)

    _prev_depth_map = result
    return result
