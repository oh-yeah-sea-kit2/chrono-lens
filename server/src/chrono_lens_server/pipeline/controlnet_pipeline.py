"""
Phase 3: SD1.5 + LCM LoRA + ControlNet Canny img2img pipeline.
"""

import io
import logging
import os

import numpy as np

logger = logging.getLogger(__name__)

CONTROLNET_STEPS = int(os.getenv("CONTROLNET_STEPS", "6"))
CONTROLNET_STRENGTH = float(os.getenv("CONTROLNET_STRENGTH", "0.75"))
CONTROLNET_SCALE = float(os.getenv("CONTROLNET_SCALE", "0.7"))
OUTPUT_QUALITY = int(os.getenv("OUTPUT_QUALITY", "85"))


def _jpeg_to_pil(jpeg: bytes):
    from PIL import Image
    return Image.open(io.BytesIO(jpeg)).convert("RGB").resize((512, 512))


def _pil_to_jpeg(img, quality: int = OUTPUT_QUALITY) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


def _adain_color_transfer(source_pil, target_pil) -> "PIL.Image.Image":
    """
    AdaIN color transfer: align source's Lab color distribution to target's.
    Reduces inter-frame color flicker.
    """
    import cv2
    from PIL import Image

    source = np.array(source_pil).astype(float)
    target = np.array(target_pil).astype(float)

    source_lab = cv2.cvtColor(source.astype(np.uint8), cv2.COLOR_RGB2LAB).astype(float)
    target_lab = cv2.cvtColor(target.astype(np.uint8), cv2.COLOR_RGB2LAB).astype(float)

    for ch in range(3):
        s_mean = source_lab[:, :, ch].mean()
        s_std = source_lab[:, :, ch].std() + 1e-5
        t_mean = target_lab[:, :, ch].mean()
        t_std = target_lab[:, :, ch].std() + 1e-5
        source_lab[:, :, ch] = (source_lab[:, :, ch] - s_mean) / s_std * t_std + t_mean

    result_lab = np.clip(source_lab, 0, 255).astype(np.uint8)
    result_rgb = cv2.cvtColor(result_lab, cv2.COLOR_LAB2RGB)
    return Image.fromarray(result_rgb)


_prev_result_pil = None


async def process(frame) -> bytes:
    """
    Phase 3 process function. Drop-in replacement for lcm_pipeline.process.
    """
    global _prev_result_pil
    import torch
    from .edge_detector import jpeg_to_canny
    from .model_loader import FIXED_SEED, get_controlnet_pipeline, get_device
    from .prompt_templates import get_prompts

    pipe = get_controlnet_pipeline()
    if pipe is None:
        logger.warning("ControlNet pipeline not loaded, falling back to echo")
        return frame.jpeg

    prompt, negative_prompt = get_prompts(frame.era_id)
    init_image = _jpeg_to_pil(frame.jpeg)
    control_image = jpeg_to_canny(frame.jpeg)

    device = get_device()
    generator = torch.Generator(device=device).manual_seed(FIXED_SEED)

    result = pipe(
        prompt=prompt,
        negative_prompt=negative_prompt,
        image=init_image,
        control_image=control_image,
        strength=CONTROLNET_STRENGTH,
        num_inference_steps=CONTROLNET_STEPS,
        guidance_scale=1.5,
        controlnet_conditioning_scale=CONTROLNET_SCALE,
        generator=generator,
    )

    result_pil = result.images[0]

    # AdaIN color transfer to reduce flicker
    if _prev_result_pil is not None:
        result_pil = _adain_color_transfer(result_pil, _prev_result_pil)
    _prev_result_pil = result_pil

    return _pil_to_jpeg(result_pil)
