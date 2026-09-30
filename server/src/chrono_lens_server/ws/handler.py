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


async def _handle_capture(websocket: WebSocket, cmd: dict) -> None:
    """Handle a capture request: receive JPEG, run HQ pipeline, return result."""
    import base64

    era_id = cmd.get("era_id", 1)
    jpeg_length = cmd.get("jpeg_length", 0)
    logger.info("Capture request: era_id=%s expected_jpeg=%d", era_id, jpeg_length)

    try:
        # Receive JPEG binary (next message)
        jpeg_data = await asyncio.wait_for(websocket.receive_bytes(), timeout=10.0)
        logger.info("Capture: received %dB jpeg, first=%s", len(jpeg_data), jpeg_data[:4].hex())

        # Run HQ pipeline or echo
        from ..pipeline.hq_pipeline import capture as hq_capture
        loop = asyncio.get_running_loop()
        try:
            result_jpeg, proc_ms = await loop.run_in_executor(
                None, hq_capture, jpeg_data, era_id,
            )
        except Exception:
            # Fallback to echo if pipeline not loaded
            logger.warning("HQ pipeline failed, falling back to echo")
            result_jpeg = jpeg_data
            proc_ms = 0

        result_json = {
            "type": "capture_result",
            "image": base64.b64encode(result_jpeg).decode(),
            "era_id": era_id,
            "processing_time_ms": proc_ms,
        }
        await websocket.send_text(json.dumps(result_json))
        logger.info("Capture: sent result (%d chars, %dms)", len(json.dumps(result_json)), proc_ms)

    except Exception as e:
        logger.exception("Capture error: %s", e)
        try:
            await websocket.send_text(json.dumps({
                "type": "capture_error",
                "error": str(e),
            }))
        except Exception:
            pass


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
            msg = await websocket.receive()
        except WebSocketDisconnect:
            break

        if "text" in msg:
            # JSON command (e.g. capture request)
            try:
                cmd = json.loads(msg["text"])
                if cmd.get("type") == "capture":
                    await _handle_capture(websocket, cmd)
            except Exception as e:
                logger.exception("Text message error: %s", e)
            continue

        if "bytes" in msg:
            raw = msg["bytes"]
            metrics.record_received()
            try:
                frame = parse_client_frame(raw)
            except ValueError as e:
                logger.warning("Parse error: %s (raw_len=%d)", e, len(raw))
                continue

            if queue.full():
                try:
                    queue.get_nowait()
                    metrics.record_dropped()
                    logger.debug("Dropped stale frame_id=%d", frame.frame_id)
                except asyncio.QueueEmpty:
                    pass
            queue.put_nowait(frame)
            logger.debug(
                "Recv frame_id=%d era=%d size=%dx%d jpeg=%dB",
                frame.frame_id, frame.era_id, frame.width, frame.height, len(frame.jpeg),
            )


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

        logger.debug(
            "Send frame_id=%d proc_us=%d result_jpeg=%dB",
            frame.frame_id, proc_us, len(result_jpeg),
        )

        try:
            await websocket.send_bytes(raw)
        except Exception:
            break

        # Periodic summary every 10 frames
        if metrics.frames_processed % 10 == 0:
            logger.info(
                "Stats: %s",
                metrics.to_dict(),
            )
