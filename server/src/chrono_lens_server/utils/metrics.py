"""Simple in-memory metrics for latency and FPS tracking."""

import time
from collections import deque
from dataclasses import dataclass, field
from threading import Lock


@dataclass
class ConnectionMetrics:
    frames_received: int = 0
    frames_processed: int = 0
    frames_dropped: int = 0
    total_proc_us: int = 0
    rtt_samples: deque = field(default_factory=lambda: deque(maxlen=20))
    _lock: Lock = field(default_factory=Lock, repr=False)

    def record_processed(self, proc_us: int) -> None:
        with self._lock:
            self.frames_processed += 1
            self.total_proc_us += proc_us

    def record_dropped(self) -> None:
        with self._lock:
            self.frames_dropped += 1

    def record_received(self) -> None:
        with self._lock:
            self.frames_received += 1

    @property
    def avg_proc_ms(self) -> float:
        if self.frames_processed == 0:
            return 0.0
        return self.total_proc_us / self.frames_processed / 1000

    def to_dict(self) -> dict:
        return {
            "frames_received": self.frames_received,
            "frames_processed": self.frames_processed,
            "frames_dropped": self.frames_dropped,
            "avg_proc_ms": round(self.avg_proc_ms, 2),
        }
