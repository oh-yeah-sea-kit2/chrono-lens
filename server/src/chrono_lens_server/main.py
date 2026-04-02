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


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Server starting up (Phase 1: echo mode)")
    # Phase 2+: load models here, then call set_process_func(ai_pipeline.process)
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
    return {"status": "ok", "version": "0.1.0", "mode": "echo"}


@app.websocket("/stream")
async def stream_endpoint(websocket: WebSocket):
    await handle_connection(websocket)
