"""
Phase 2: SD1.5 + LCM img2img pipeline.

Temporal consistency:
- Low strength (0.35) to preserve camera structure
- Fixed seed across frames
- Blend current result with previous to smooth transitions
"""

import asyncio
import io
import logging
import os

import numpy as np

logger = logging.getLogger(__name__)

LCM_STEPS = int(os.getenv("LCM_STEPS", "4"))
LCM_STRENGTH = float(os.getenv("LCM_STRENGTH", "0.35"))
OUTPUT_QUALITY = int(os.getenv("OUTPUT_QUALITY", "85"))
# How much of the previous frame to blend in (0.0 = none, 0.5 = half)
TEMPORAL_BLEND = float(os.getenv("TEMPORAL_BLEND", "0.3"))

_prev_result = None  # numpy array of previous result


def _jpeg_to_pil(jpeg: bytes):
    from PIL import Image
    return Image.open(io.BytesIO(jpeg)).convert("RGB").resize((512, 512))


def _pil_to_jpeg(img, quality: int = OUTPUT_QUALITY) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


def _temporal_blend(current_pil, prev_np, alpha: float):
    """Blend current result with previous frame for temporal smoothness."""
    from PIL import Image

    current_np = np.array(current_pil, dtype=np.float32)
    blended = (1.0 - alpha) * current_np + alpha * prev_np.astype(np.float32)
    return Image.fromarray(np.clip(blended, 0, 255).astype(np.uint8))


def _infer(frame) -> bytes:
    """Synchronous inference — called from a thread pool."""
    global _prev_result
    import torch
    from .model_loader import FIXED_SEED, get_device, get_lcm_pipeline
    from .prompt_templates import get_prompts

    pipe = get_lcm_pipeline()
    if pipe is None:
        logger.warning("Pipeline not loaded, falling back to echo")
        return frame.jpeg

    prompt, negative_prompt = get_prompts(frame.era_id)
    init_image = _jpeg_to_pil(frame.jpeg)

    device = get_device()
    generator = torch.Generator(device=device).manual_seed(FIXED_SEED)

    result = pipe(
        prompt=prompt,
        negative_prompt=negative_prompt,
        image=init_image,
        strength=LCM_STRENGTH,
        num_inference_steps=LCM_STEPS,
        guidance_scale=1.0,
        generator=generator,
    )

    result_pil = result.images[0]

    # Temporal blending with previous frame
    if _prev_result is not None and TEMPORAL_BLEND > 0:
        result_pil = _temporal_blend(result_pil, _prev_result, TEMPORAL_BLEND)

    _prev_result = np.array(result_pil)

    return _pil_to_jpeg(result_pil)


async def process(frame) -> bytes:
    """Async wrapper — runs inference in a thread to keep the event loop free."""
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, _infer, frame)
