"""
Model loader for Phase 2+.

Models are loaded once at startup and held in memory.
Supports CUDA, MPS (Apple Silicon), and CPU fallback.
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


def _get_device_and_dtype():
    """Auto-detect the best available device."""
    import torch

    if torch.cuda.is_available():
        logger.info("Using CUDA")
        return "cuda", torch.float16
    elif torch.backends.mps.is_available():
        logger.info("Using MPS (Apple Silicon)")
        # MPS supports float16 for most ops in recent PyTorch
        return "mps", torch.float16
    else:
        logger.info("Using CPU (slow)")
        return "cpu", torch.float32


def get_device() -> str:
    """Return the device string for generator creation."""
    import torch
    if torch.cuda.is_available():
        return "cuda"
    elif torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def load_lcm_pipeline():
    """Load SD1.5 + LCM pipeline."""
    import torch
    from diffusers import DiffusionPipeline

    device, dtype = _get_device_and_dtype()

    logger.info("Loading LCM pipeline: %s → %s (%s)", MODEL_ID, device, dtype)
    t0 = time.monotonic()

    pipe = DiffusionPipeline.from_pretrained(
        MODEL_ID,
        torch_dtype=dtype,
    ).to(device)

    if device == "cuda":
        try:
            pipe.enable_xformers_memory_efficient_attention()
            logger.info("xformers enabled")
        except Exception:
            logger.warning("xformers not available")

    # Warmup inference
    logger.info("Running warmup inference...")
    from PIL import Image
    dummy = Image.new("RGB", (512, 512), color=(128, 128, 128))
    gen = torch.Generator(device=device).manual_seed(FIXED_SEED)
    pipe(
        prompt="warmup",
        image=dummy,
        strength=0.5,
        num_inference_steps=4,
        guidance_scale=1.0,
        generator=gen,
    )

    elapsed = time.monotonic() - t0
    logger.info("LCM pipeline ready in %.1fs on %s", elapsed, device)
    return pipe


def load_controlnet_pipeline():
    """Load SD1.5 + LCM LoRA + ControlNet Canny pipeline."""
    import torch
    from diffusers import ControlNetModel, StableDiffusionControlNetImg2ImgPipeline
    from diffusers.schedulers import LCMScheduler

    device, dtype = _get_device_and_dtype()

    logger.info("Loading ControlNet pipeline: %s → %s", CONTROLNET_MODEL_ID, device)
    t0 = time.monotonic()

    controlnet = ControlNetModel.from_pretrained(
        CONTROLNET_MODEL_ID,
        torch_dtype=dtype,
    )
    pipe = StableDiffusionControlNetImg2ImgPipeline.from_pretrained(
        "runwayml/stable-diffusion-v1-5",
        controlnet=controlnet,
        torch_dtype=dtype,
    ).to(device)

    pipe.scheduler = LCMScheduler.from_config(pipe.scheduler.config)
    pipe.load_lora_weights("latent-consistency/lcm-lora-sdv1-5")
    pipe.fuse_lora()

    if device == "cuda":
        try:
            pipe.enable_xformers_memory_efficient_attention()
        except Exception:
            logger.warning("xformers not available")

    elapsed = time.monotonic() - t0
    logger.info("ControlNet pipeline ready in %.1fs on %s", elapsed, device)
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
