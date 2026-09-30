"""Tests for binary protocol encode/decode."""

import struct
import time

import pytest

from src.chrono_lens_server.ws.protocol import (
    CLIENT_HEADER_SIZE,
    MAGIC,
    MSG_TYPE_ECHO,
    SERVER_HEADER_SIZE,
    VERSION,
    ClientFrame,
    ServerResult,
    build_server_result,
    parse_client_frame,
    CLIENT_HEADER_FMT,
)


def _make_client_raw(
    frame_id: int = 1,
    jpeg: bytes = b"\xff\xd8\xff\xe0" + b"\x00" * 16,
    era_id: int = 1,
) -> bytes:
    client_ts_us = int(time.time() * 1e6)
    header = struct.pack(
        CLIENT_HEADER_FMT,
        MAGIC,
        VERSION,
        0x01,
        frame_id,
        client_ts_us,
        512,
        512,
        era_id,
        75,
        0,
        len(jpeg),
    )
    return header + jpeg


def test_client_header_size():
    assert CLIENT_HEADER_SIZE == 32


def test_server_header_size():
    assert SERVER_HEADER_SIZE == 40


def test_parse_client_frame_roundtrip():
    jpeg = b"\xff\xd8\xff\xe0" + b"\xab" * 100
    raw = _make_client_raw(frame_id=42, jpeg=jpeg, era_id=1)
    frame = parse_client_frame(raw)

    assert frame.frame_id == 42
    assert frame.era_id == 1
    assert frame.width == 512
    assert frame.height == 512
    assert frame.quality == 75
    assert frame.jpeg == jpeg


def test_build_server_result():
    jpeg = b"\xff\xd8" + b"\xcc" * 50
    result = ServerResult(
        frame_id=99,
        client_ts_us=123456,
        server_ts_us=654321,
        proc_us=15000,
        era_id=2,
        flags=0,
        jpeg=jpeg,
        msg_type=MSG_TYPE_ECHO,
    )
    raw = build_server_result(result)
    assert len(raw) == SERVER_HEADER_SIZE + len(jpeg)
    assert raw[:2] == MAGIC


def test_parse_invalid_magic():
    raw = b"\x00\x00" + b"\x00" * 30
    with pytest.raises(ValueError, match="Invalid magic"):
        parse_client_frame(raw)


def test_parse_too_short():
    with pytest.raises(ValueError, match="Frame too short"):
        parse_client_frame(b"\x43\x4c" + b"\x00" * 10)
