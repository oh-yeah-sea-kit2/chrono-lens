"""
chrono-lens WebSocket server entry point.

Phase 1: echo server
Phase 2+: replace process_func with LCM/ControlNet pipeline
"""

import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket
from fastapi.middleware.cors import CORSMiddleware

from .ws.handler import handle_connection, set_process_func

LOG_LEVEL = os.getenv("LOG_LEVEL", "info").upper()
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

# PIPELINE env var controls which phase runs:
#   "echo"       → Phase 1 (default, no GPU required)
#   "lcm"        → Phase 2 (SD1.5 + LCM, requires CUDA)
#   "controlnet" → Phase 3 (SD1.5 + LCM LoRA + ControlNet Canny, requires CUDA)
PIPELINE = os.getenv("PIPELINE", "echo").lower()


@asynccontextmanager
async def lifespan(app: FastAPI):
    if PIPELINE == "echo":
        logger.info("Server starting up in ECHO mode (Phase 1)")
    elif PIPELINE == "lcm":
        logger.info("Server starting up in LCM mode (Phase 2)")
        from .pipeline.model_loader import load_models
        from .pipeline.lcm_pipeline import process
        load_models(use_controlnet=False)
        set_process_func(process)
    elif PIPELINE == "controlnet":
        logger.info("Server starting up in ControlNet mode (Phase 3)")
        from .pipeline.model_loader import load_models
        from .pipeline.controlnet_pipeline import process
        load_models(use_controlnet=True)
        set_process_func(process)
    else:
        logger.warning("Unknown PIPELINE=%s, falling back to echo", PIPELINE)

    yield
    logger.info("Server shutting down")


app = FastAPI(title="chrono-lens", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {"status": "ok", "version": "0.1.0", "mode": PIPELINE}


@app.websocket("/stream")
async def stream_endpoint(websocket: WebSocket):
    await handle_connection(websocket)
