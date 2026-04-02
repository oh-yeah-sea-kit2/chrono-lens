"""
Phase 2: SD1.5 + LCM img2img pipeline.

process(frame) replaces the echo function in handler.py.
"""

import io
import logging
import os
import time

import numpy as np

logger = logging.getLogger(__name__)

FIXED_SEED = int(os.getenv("FIXED_SEED", "42"))
LCM_STEPS = int(os.getenv("LCM_STEPS", "4"))
LCM_STRENGTH = float(os.getenv("LCM_STRENGTH", "0.55"))
OUTPUT_QUALITY = int(os.getenv("OUTPUT_QUALITY", "85"))


def _jpeg_to_pil(jpeg: bytes):
    from PIL import Image
    return Image.open(io.BytesIO(jpeg)).convert("RGB").resize((512, 512))


def _pil_to_jpeg(img, quality: int = OUTPUT_QUALITY) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


async def process(frame) -> bytes:
    """
    Phase 2 process function. Drop-in replacement for echo.
    frame: ClientFrame from protocol.py
    """
    import torch
    from .model_loader import FIXED_SEED, get_lcm_pipeline
    from .prompt_templates import get_prompts

    pipe = get_lcm_pipeline()
    if pipe is None:
        logger.warning("Pipeline not loaded, falling back to echo")
        return frame.jpeg

    prompt, negative_prompt = get_prompts(frame.era_id)
    init_image = _jpeg_to_pil(frame.jpeg)

    generator = torch.Generator(device="cuda").manual_seed(FIXED_SEED)

    result = pipe(
        prompt=prompt,
        negative_prompt=negative_prompt,
        image=init_image,
        strength=LCM_STRENGTH,
        num_inference_steps=LCM_STEPS,
        guidance_scale=1.0,
        generator=generator,
    )

    return _pil_to_jpeg(result.images[0])
