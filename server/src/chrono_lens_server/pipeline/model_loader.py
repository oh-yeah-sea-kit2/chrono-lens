"""
Model loader for Phase 2+.

Models are loaded once at startup and held in VRAM.
Call load_models() from the FastAPI lifespan hook.
"""

import logging
import os
import time

logger = logging.getLogger(__name__)

_pipeline = None
_controlnet_pipeline = None

FIXED_SEED = int(os.getenv("FIXED_SEED", "42"))
MODEL_ID = os.getenv("MODEL_ID", "SimianLuo/LCM_Dreamshaper_v7")
CONTROLNET_MODEL_ID = os.getenv(
    "CONTROLNET_MODEL_ID", "lllyasviel/sd-controlnet-canny"
)


def load_lcm_pipeline():
    """Load SD1.5 + LCM pipeline. Requires CUDA."""
    import torch
    from diffusers import DiffusionPipeline

    logger.info("Loading LCM pipeline: %s", MODEL_ID)
    t0 = time.monotonic()

    pipe = DiffusionPipeline.from_pretrained(
        MODEL_ID,
        torch_dtype=torch.float16,
    ).to("cuda")

    try:
        pipe.enable_xformers_memory_efficient_attention()
        logger.info("xformers enabled")
    except Exception:
        logger.warning("xformers not available, falling back to default attention")

    # Warmup: one dummy inference to trigger CUDA JIT compilation
    logger.info("Running warmup inference...")
    from PIL import Image
    dummy = Image.new("RGB", (512, 512), color=(128, 128, 128))
    pipe(
        prompt="warmup",
        image=dummy,
        strength=0.5,
        num_inference_steps=4,
        guidance_scale=1.0,
    )

    elapsed = time.monotonic() - t0
    logger.info("LCM pipeline ready in %.1fs", elapsed)
    return pipe


def load_controlnet_pipeline():
    """Load SD1.5 + LCM LoRA + ControlNet Canny pipeline."""
    import torch
    from diffusers import ControlNetModel, StableDiffusionControlNetImg2ImgPipeline
    from diffusers.schedulers import LCMScheduler

    logger.info("Loading ControlNet pipeline: %s", CONTROLNET_MODEL_ID)
    t0 = time.monotonic()

    controlnet = ControlNetModel.from_pretrained(
        CONTROLNET_MODEL_ID,
        torch_dtype=torch.float16,
    )
    pipe = StableDiffusionControlNetImg2ImgPipeline.from_pretrained(
        "runwayml/stable-diffusion-v1-5",
        controlnet=controlnet,
        torch_dtype=torch.float16,
    ).to("cuda")

    pipe.scheduler = LCMScheduler.from_config(pipe.scheduler.config)
    pipe.load_lora_weights("latent-consistency/lcm-lora-sdv1-5")
    pipe.fuse_lora()

    try:
        pipe.enable_xformers_memory_efficient_attention()
    except Exception:
        logger.warning("xformers not available")

    elapsed = time.monotonic() - t0
    logger.info("ControlNet pipeline ready in %.1fs", elapsed)
    return pipe


def get_lcm_pipeline():
    return _pipeline


def get_controlnet_pipeline():
    return _controlnet_pipeline


def load_models(use_controlnet: bool = False) -> None:
    global _pipeline, _controlnet_pipeline
    if use_controlnet:
        _controlnet_pipeline = load_controlnet_pipeline()
    else:
        _pipeline = load_lcm_pipeline()
