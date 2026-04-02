"""
WebSocket connection handler.

Manages the recv loop and process loop concurrently.
The queue acts as a backpressure buffer: when full, the oldest frame
is discarded so the latest frame is always processed next.
"""

import asyncio
import inspect
import json
import logging
import time
import uuid

from fastapi import WebSocket, WebSocketDisconnect

from ..utils.metrics import ConnectionMetrics
from ..ws.protocol import (
    FLAG_DROPPED,
    MSG_TYPE_ECHO,
    ClientFrame,
    ServerResult,
    build_server_result,
    parse_client_frame,
)

logger = logging.getLogger(__name__)

# Injected at startup by main.py (Phase 2+: replaced with AI pipeline)
_process_func = None


def set_process_func(fn) -> None:
    global _process_func
    _process_func = fn


async def _echo_process(frame: ClientFrame) -> bytes:
    """Phase 1: echo the JPEG back as-is."""
    return frame.jpeg


async def handle_connection(websocket: WebSocket) -> None:
    await websocket.accept()
    session_id = str(uuid.uuid4())
    metrics = ConnectionMetrics()
    logger.info("Client connected session=%s", session_id)

    try:
        # Handshake
        hello_raw = await asyncio.wait_for(websocket.receive_text(), timeout=10.0)
        hello = json.loads(hello_raw)
        welcome = {
            "type": "welcome",
            "session_id": session_id,
            "server_version": "0.1.0",
            "capabilities": ["echo"],
            "recommended_fps": 5,
            "recommended_quality": 75,
        }
        await websocket.send_text(json.dumps(welcome))
        logger.info("Handshake done session=%s client_id=%s", session_id, hello.get("client_id"))

        queue: asyncio.Queue[ClientFrame] = asyncio.Queue(maxsize=2)
        process_fn = _process_func or _echo_process

        recv_task = asyncio.create_task(_recv_loop(websocket, queue, metrics))
        proc_task = asyncio.create_task(_proc_loop(websocket, queue, metrics, process_fn))

        done, pending = await asyncio.wait(
            {recv_task, proc_task},
            return_when=asyncio.FIRST_COMPLETED,
        )
        for task in pending:
            task.cancel()
            try:
                await task
            except (asyncio.CancelledError, Exception):
                pass
        for task in done:
            exc = task.exception()
            if exc:
                raise exc

    except WebSocketDisconnect:
        logger.info("Client disconnected session=%s metrics=%s", session_id, metrics.to_dict())
    except asyncio.TimeoutError:
        logger.warning("Handshake timeout session=%s", session_id)
        await websocket.close(code=1008)
    except Exception as e:
        logger.exception("Unexpected error session=%s: %s", session_id, e)
        try:
            await websocket.close(code=1011)
        except Exception:
            pass


async def _recv_loop(
    websocket: WebSocket,
    queue: asyncio.Queue,
    metrics: ConnectionMetrics,
) -> None:
    while True:
        try:
            raw = await websocket.receive_bytes()
        except WebSocketDisconnect:
            break

        metrics.record_received()
        try:
            frame = parse_client_frame(raw)
        except ValueError as e:
            logger.warning("Parse error: %s", e)
            continue

        if queue.full():
            # Drop the oldest frame to keep queue fresh (LIFO behavior)
            try:
                queue.get_nowait()
                metrics.record_dropped()
            except asyncio.QueueEmpty:
                pass
        queue.put_nowait(frame)


async def _proc_loop(
    websocket: WebSocket,
    queue: asyncio.Queue,
    metrics: ConnectionMetrics,
    process_fn,
) -> None:
    while True:
        frame = await queue.get()
        t0 = time.monotonic()

        try:
            if inspect.iscoroutinefunction(process_fn):
                result_jpeg = await process_fn(frame)
            else:
                result_jpeg = process_fn(frame)
            flags = 0
        except Exception as e:
            logger.exception("Process error frame_id=%d: %s", frame.frame_id, e)
            result_jpeg = frame.jpeg  # fallback to echo
            flags = FLAG_DROPPED

        proc_us = int((time.monotonic() - t0) * 1e6)
        metrics.record_processed(proc_us)

        result = ServerResult(
            frame_id=frame.frame_id,
            client_ts_us=frame.client_ts_us,
            server_ts_us=int(time.time() * 1e6),
            proc_us=proc_us,
            era_id=frame.era_id,
            flags=flags,
            jpeg=result_jpeg,
            msg_type=MSG_TYPE_ECHO,
        )
        raw = build_server_result(result)

        try:
            await websocket.send_bytes(raw)
        except Exception:
            break
