"""Integration tests for WebSocket echo server."""

import json
import struct
import time

import pytest
from fastapi.testclient import TestClient

from src.chrono_lens_server.main import app
from src.chrono_lens_server.ws.protocol import (
    CLIENT_HEADER_FMT,
    SERVER_HEADER_FMT,
    SERVER_HEADER_SIZE,
    MAGIC,
    VERSION,
)


def _make_frame(frame_id: int = 1, jpeg: bytes = b"\xff\xd8" + b"\xaa" * 100) -> bytes:
    ts = int(time.time() * 1e6)
    header = struct.pack(
        CLIENT_HEADER_FMT,
        MAGIC, VERSION, 0x01,
        frame_id, ts, 512, 512, 0x01, 75, 0, len(jpeg),
    )
    return header + jpeg


def test_health():
    with TestClient(app) as client:
        resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_websocket_handshake_and_echo():
    with TestClient(app) as client:
        with client.websocket_connect("/stream") as ws:
            # Send HELLO
            ws.send_text(json.dumps({
                "type": "hello",
                "client_id": "test-client",
                "device_model": "pytest",
                "app_version": "0.0.1",
            }))
            welcome = json.loads(ws.receive_text())
            assert welcome["type"] == "welcome"
            assert "session_id" in welcome

            # Send frame and receive echo
            jpeg = b"\xff\xd8\xff\xe0" + b"\xbb" * 200
            frame_raw = _make_frame(frame_id=7, jpeg=jpeg)
            ws.send_bytes(frame_raw)

            result_raw = ws.receive_bytes()
            assert len(result_raw) >= SERVER_HEADER_SIZE

            # Verify echoed JPEG
            payload = result_raw[SERVER_HEADER_SIZE:]
            assert payload == jpeg
