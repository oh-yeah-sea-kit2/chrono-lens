"""
chrono-lens server entry point.

Hybrid architecture:
- POST /capture: high-quality single-frame transformation (shutter mode)
- WebSocket /stream: legacy real-time streaming (may be removed)
- GET /health: server status
"""

import asyncio
import base64
import logging
import os
import socket
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Form, UploadFile, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from zeroconf import ServiceInfo
from zeroconf.asyncio import AsyncZeroconf

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
PORT = int(os.getenv("PORT", "8765"))

SERVICE_TYPE = "_chrono-lens._tcp.local."
SERVICE_NAME = "chrono-lens._chrono-lens._tcp.local."

_async_zc: AsyncZeroconf | None = None
_service_info: ServiceInfo | None = None


def _get_local_ip() -> str:
    """Get the LAN IP address of this machine."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


async def _register_mdns(port: int) -> None:
    global _async_zc, _service_info
    ip = _get_local_ip()
    _service_info = ServiceInfo(
        SERVICE_TYPE,
        SERVICE_NAME,
        addresses=[socket.inet_aton(ip)],
        port=port,
        properties={"pipeline": PIPELINE, "version": "0.1.0"},
    )
    _async_zc = AsyncZeroconf()
    await _async_zc.async_register_service(_service_info)
    logger.info("mDNS registered: %s @ %s:%d", SERVICE_NAME, ip, port)


async def _unregister_mdns() -> None:
    global _async_zc, _service_info
    if _async_zc:
        if _service_info:
            await _async_zc.async_unregister_service(_service_info)
        await _async_zc.async_close()
        _async_zc = None
        _service_info = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    await _register_mdns(PORT)

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
    await _unregister_mdns()
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


@app.post("/capture")
async def capture_endpoint(
    image: UploadFile = File(...),
    era_id: int = Form(default=1),
    quality: str = Form(default="high"),
):
    """High-quality single-frame transformation for shutter mode."""
    if PIPELINE == "echo":
        # Echo mode: return the image as-is
        jpeg_data = await image.read()
        return JSONResponse({
            "image": base64.b64encode(jpeg_data).decode(),
            "era_id": era_id,
            "processing_time_ms": 0,
        })

    from .pipeline.hq_pipeline import capture as hq_capture

    jpeg_data = await image.read()
    loop = asyncio.get_running_loop()
    result_jpeg, proc_ms = await loop.run_in_executor(
        None, hq_capture, jpeg_data, era_id,
    )

    return JSONResponse({
        "image": base64.b64encode(result_jpeg).decode(),
        "era_id": era_id,
        "processing_time_ms": proc_ms,
    })


@app.websocket("/stream")
async def stream_endpoint(websocket: WebSocket):
    await handle_connection(websocket)
