"""
High-quality capture pipeline for shutter mode.

Compared to lcm_pipeline (real-time):
- More inference steps (20 vs 4) for better quality
- Higher strength (0.55 vs 0.35) for more dramatic transformation
- Larger resolution (768x768 vs 512x512)
- Optional ControlNet Canny for structure preservation
"""

import io
import logging
import os
import time

logger = logging.getLogger(__name__)

HQ_STEPS = int(os.getenv("HQ_STEPS", "20"))
HQ_STRENGTH = float(os.getenv("HQ_STRENGTH", "0.55"))
HQ_GUIDANCE = float(os.getenv("HQ_GUIDANCE", "1.5"))
HQ_SIZE = int(os.getenv("HQ_SIZE", "768"))
OUTPUT_QUALITY = int(os.getenv("HQ_OUTPUT_QUALITY", "95"))


def _jpeg_to_pil(jpeg: bytes, size: int = HQ_SIZE):
    from PIL import Image
    return Image.open(io.BytesIO(jpeg)).convert("RGB").resize((size, size))


def _pil_to_jpeg(img, quality: int = OUTPUT_QUALITY) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


def capture(jpeg: bytes, era_id: int) -> tuple[bytes, int]:
    """
    Run high-quality img2img transformation.
    Returns (result_jpeg, processing_time_ms).
    """
    import torch
    from .model_loader import FIXED_SEED, get_device, get_lcm_pipeline
    from .prompt_templates import get_prompts

    pipe = get_lcm_pipeline()
    if pipe is None:
        raise RuntimeError("Pipeline not loaded")

    t0 = time.monotonic()

    prompt, negative_prompt = get_prompts(era_id)
    init_image = _jpeg_to_pil(jpeg)

    device = get_device()
    generator = torch.Generator(device=device).manual_seed(FIXED_SEED)

    result = pipe(
        prompt=prompt,
        negative_prompt=negative_prompt,
        image=init_image,
        strength=HQ_STRENGTH,
        num_inference_steps=HQ_STEPS,
        guidance_scale=HQ_GUIDANCE,
        generator=generator,
    )

    result_jpeg = _pil_to_jpeg(result.images[0])
    elapsed_ms = int((time.monotonic() - t0) * 1000)

    logger.info("HQ capture: era=%d steps=%d size=%d time=%dms", era_id, HQ_STEPS, HQ_SIZE, elapsed_ms)
    return result_jpeg, elapsed_ms
