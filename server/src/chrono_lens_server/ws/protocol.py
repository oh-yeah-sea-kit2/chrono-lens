"""
WebSocket binary protocol definitions for chrono-lens.

Client → Server (FRAME):
  [32-byte header][JPEG payload]

Server → Client (RESULT / ECHO):
  [40-byte header][JPEG payload]
"""

import struct
import time
from dataclasses import dataclass

# Magic bytes: 'CL'
MAGIC = b"\x43\x4C"
VERSION = 0x01

# Message types
MSG_TYPE_FRAME = 0x01   # client → server
MSG_TYPE_RESULT = 0x02  # server → client (AI processed)
MSG_TYPE_ECHO = 0x10    # server → client (Phase 1 echo)

# Frame drop flag
FLAG_DROPPED = 0x01
FLAG_KEYFRAME = 0x02

# Era IDs
ERA_PASSTHROUGH = 0x00
ERA_TAISHO = 0x01       # 大正 (1912-1926)
ERA_SHOWA_EARLY = 0x02  # 昭和初期 (1926-1945)
ERA_SHOWA_MID = 0x03    # 昭和中期 (1945-1970)
ERA_MEIJI = 0x04        # 明治 (1868-1912)

# Header formats (little-endian)
# CLIENT: magic(2s) version(B) msg_type(B) frame_id(Q) client_ts_us(Q)
#         width(H) height(H) era_id(B) quality(B) _reserved(H) payload_len(I)
# = 2+1+1+8+8+2+2+1+1+2+4 = 32 bytes
CLIENT_HEADER_FMT = "<2sBBQQHHBBHI"
CLIENT_HEADER_SIZE = struct.calcsize(CLIENT_HEADER_FMT)
assert CLIENT_HEADER_SIZE == 32, f"Expected 32, got {CLIENT_HEADER_SIZE}"

# SERVER: magic(2s) version(B) msg_type(B) frame_id(Q) client_ts_us(Q)
#         server_ts_us(Q) proc_us(I) era_id(B) flags(B) _reserved(H) payload_len(I)
# = 2+1+1+8+8+8+4+1+1+2+4 = 40 bytes
SERVER_HEADER_FMT = "<2sBBQQQIBBHI"
SERVER_HEADER_SIZE = struct.calcsize(SERVER_HEADER_FMT)
assert SERVER_HEADER_SIZE == 40, f"Expected 40, got {SERVER_HEADER_SIZE}"


@dataclass
class ClientFrame:
    frame_id: int
    client_ts_us: int
    width: int
    height: int
    era_id: int
    quality: int
    jpeg: bytes


@dataclass
class ServerResult:
    frame_id: int
    client_ts_us: int
    server_ts_us: int
    proc_us: int
    era_id: int
    flags: int
    jpeg: bytes
    msg_type: int = MSG_TYPE_ECHO


def parse_client_frame(raw: bytes) -> ClientFrame:
    if len(raw) < CLIENT_HEADER_SIZE:
        raise ValueError(f"Frame too short: {len(raw)} < {CLIENT_HEADER_SIZE}")

    header = raw[:CLIENT_HEADER_SIZE]
    (magic, version, msg_type, frame_id, client_ts_us,
     width, height, era_id, quality, _reserved, payload_len) = struct.unpack(
        CLIENT_HEADER_FMT, header
    )

    if magic != MAGIC:
        raise ValueError(f"Invalid magic: {magic!r}")
    if version != VERSION:
        raise ValueError(f"Unknown version: {version}")

    jpeg = raw[CLIENT_HEADER_SIZE: CLIENT_HEADER_SIZE + payload_len]
    return ClientFrame(
        frame_id=frame_id,
        client_ts_us=client_ts_us,
        width=width,
        height=height,
        era_id=era_id,
        quality=quality,
        jpeg=jpeg,
    )


def build_server_result(result: ServerResult) -> bytes:
    header = struct.pack(
        SERVER_HEADER_FMT,
        MAGIC,
        VERSION,
        result.msg_type,
        result.frame_id,
        result.client_ts_us,
        result.server_ts_us,
        result.proc_us,
        result.era_id,
        result.flags,
        0,  # reserved
        len(result.jpeg),
    )
    return header + result.jpeg
