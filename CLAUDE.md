# chrono-lens — CLAUDE.md

**ステータス: 技術検証完了（アーカイブ）**

## プロジェクト概要

「目の前の風景を昔っぽく見せる」カメラアプリの技術検証。ハイブリッドアーキテクチャ:
- **プレビュー**: デバイス上でCoreMLスタイル転送（リアルタイム、雰囲気レベル）
- **シャッター**: サーバーでSD1.5 img2img高品質変換（3-5秒、本気の変換）

## プロジェクト構成

```
chrono-lens/
├── server/    Python FastAPI サーバー（POST /capture で高品質AI変換）
├── mobile/    Flutter カメラアプリ（iOS / Android）
└── tools/     CoreMLモデル変換・スタイル画像生成スクリプト
```

---

## サーバー (server/)

### ツール: uv

Python パッケージ管理は **uv** を使う。pip / poetry は使わない。

```bash
cd server

uv sync                  # 基本依存のみ
uv sync --extra mps      # Apple Silicon (MPS)
uv sync --extra gpu      # NVIDIA GPU (CUDA)
uv sync --extra dev      # テスト・Lint

uv run uvicorn src.chrono_lens_server.main:app --host 0.0.0.0 --port 8765
uv run pytest
```

### エンドポイント

| エンドポイント | 用途 |
|---|---|
| `GET /health` | ステータス確認 |
| `POST /capture` | シャッター高品質変換（image + era_id） |
| `WebSocket /stream` | レガシー リアルタイムストリーム |

### パイプライン切り替え

環境変数 `PIPELINE` で制御:

| 値 | 内容 | GPU |
|---|---|---|
| `echo`（デフォルト） | エコーのみ | 不要 |
| `lcm` | SD1.5 + LCM img2img | 必須（MPS or CUDA）|
| `controlnet` | ControlNet Canny | 必須 |

### 依存追加のルール

`requirements/*.txt` は使わない。`server/pyproject.toml` の `[project.dependencies]` または `[project.optional-dependencies]` に追加する。

---

## モバイル (mobile/)

### ツール: fvm

Flutter バージョン管理は **fvm** を使う。グローバルの flutter コマンドは使わない。

```bash
cd mobile
fvm flutter pub get
fvm flutter run
```

### アーキテクチャ

```
Camera 30fps
  → 3フレームに1回 JPEG変換 (Isolate)
  → CoreML Style Transfer (Platform Channel, Swift)
  → Image.memory で表示

[シャッター]
  → takePicture()
  → HTTP POST /capture (サーバー)
  → ResultPage (Before/After比較、保存、共有)
```

### Platform Channel

| チャンネル | 用途 |
|---|---|
| `com.chrono_lens/style_transfer` | CoreMLスタイル転送 |

メソッド: `loadModel`, `setStyle`, `transferFrame`, `isReady`

### CoreMLモデル

`tools/convert_style_model.py` でMagenta Arbitrary Style Transferモデルを変換。
変換済み `.mlpackage` は `mobile/ios/Runner/Models/` に配置。

### 実機テスト前提条件

- iPhoneとMacが同じWi-Fiに接続
- サーバーが `--host 0.0.0.0` で起動
- mDNSでサーバー自動検出（手動IP入力も可）

---

## Era ID

| ID | 時代 | スタイル画像 |
|---|---|---|
| 0x00 | パススルー | なし |
| 0x01 | 大正（1912–1926）| `assets/styles/taisho.jpg` |
| 0x02 | 昭和初期（1926–1945）| `assets/styles/showa_early.jpg` |
| 0x03 | 昭和中期（1945–1970）| `assets/styles/showa_mid.jpg` |
| 0x04 | 明治（1868–1912）| `assets/styles/meiji.jpg` |

---

## コミット・PRルール

- コミット・プッシュはユーザーの明示的な指示があった場合のみ行う
- PRの作成・マージも同様
