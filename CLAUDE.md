# chrono-lens — CLAUDE.md

## プロジェクト構成

```
chrono-lens/
├── server/   Python FastAPI WebSocket サーバー（AI推論）
└── mobile/   Flutter カメラアプリ（iOS / Android）
```

---

## サーバー (server/)

### ツール: uv

Python パッケージ管理は **uv** を使う。pip / poetry は使わない。

```bash
cd server

uv sync                  # Phase 1（GPU不要）
uv sync --extra gpu      # Phase 2以降（CUDA必須）
uv sync --extra dev      # テスト・Lint

uv run uvicorn src.chrono_lens_server.main:app --host 0.0.0.0 --port 8765
uv run pytest
```

### パイプライン切り替え

環境変数 `PIPELINE` でフェーズを切り替える：

| 値 | フェーズ | GPU |
|---|---|---|
| `echo`（デフォルト） | Phase 1: エコーのみ | 不要 |
| `lcm` | Phase 2: SD1.5 + LCM | 必須 |
| `controlnet` | Phase 3: ControlNet Canny | 必須 |

```bash
PIPELINE=echo uv run uvicorn src.chrono_lens_server.main:app --host 0.0.0.0 --port 8765
```

### 依存追加のルール

`requirements/*.txt` は使わない。`server/pyproject.toml` の `[project.dependencies]` または `[project.optional-dependencies]` に追加する。

---

## モバイル (mobile/)

### ツール: fvm

Flutter バージョン管理は **fvm** を使う。グローバルの flutter コマンドは使わない。

```bash
cd mobile

fvm flutter pub get
fvm flutter run          # 実機転送
fvm flutter build ios    # リリースビルド
```

バージョンは `mobile/.fvmrc` で `stable` に固定済み。新しいバージョンに変更する場合は `.fvmrc` を編集してから `fvm install`。

### 実機テスト前提条件

- iPhoneとMacが**同じWi-Fi**に接続されていること
- サーバーが `--host 0.0.0.0` で起動していること
- アプリ初回起動時にMacのローカルIPを入力（設定はSharedPreferencesに保存される）

---

## WebSocket バイナリプロトコル

### クライアント → サーバー（32バイトヘッダー + JPEG）

| Offset | 型 | 内容 |
|---|---|---|
| 0-1 | `bytes` | Magic `0x43 0x4C`（"CL"）|
| 2 | `uint8` | Version = 1 |
| 3 | `uint8` | msg_type = 0x01 |
| 4-11 | `uint64 LE` | frame_id（単調増加）|
| 12-19 | `uint64 LE` | client_ts_us（Unix マイクロ秒）|
| 20-21 | `uint16 LE` | width |
| 22-23 | `uint16 LE` | height |
| 24 | `uint8` | era_id |
| 25 | `uint8` | JPEG quality hint |
| 26-27 | `uint16 LE` | reserved |
| 28-31 | `uint32 LE` | payload_len |
| 32〜 | `bytes` | JPEG データ |

### サーバー → クライアント（40バイトヘッダー + JPEG）

| Offset | 型 | 内容 |
|---|---|---|
| 0-1 | `bytes` | Magic `0x43 0x4C` |
| 2 | `uint8` | Version = 1 |
| 3 | `uint8` | msg_type（0x02=RESULT, 0x10=ECHO）|
| 4-11 | `uint64 LE` | frame_id（クライアントのechoback）|
| 12-19 | `uint64 LE` | client_ts_us（echoback）|
| 20-27 | `uint64 LE` | server_ts_us |
| 28-31 | `uint32 LE` | proc_us（サーバー処理時間）|
| 32 | `uint8` | era_id |
| 33 | `uint8` | flags（bit0=dropped）|
| 34-35 | `uint16 LE` | reserved |
| 36-39 | `uint32 LE` | payload_len |
| 40〜 | `bytes` | JPEG データ |

---

## Era ID

| ID | 時代 |
|---|---|
| 0x00 | パススルー（変換なし）|
| 0x01 | 大正（1912–1926）|
| 0x02 | 昭和初期（1926–1945）|
| 0x03 | 昭和中期（1945–1970）|
| 0x04 | 明治（1868–1912）|

---

## コミット・PRルール

- コミット・プッシュはユーザーの明示的な指示があった場合のみ行う
- PRの作成・マージも同様
