# chrono-lens

**ステータス: 技術検証完了（アーカイブ）**

「今ある技術で、なるべくリアルタイムに過去の風景を映す」というコンセプトの技術検証プロジェクト。Flutter + Python + Stable Diffusion で実装し、何ができて何ができないかを明らかにした。

---

## やったこと

### Phase 1: WebSocketリアルタイムストリーミング
- Flutter ↔ Python FastAPI 間のWebSocketバイナリプロトコル（32/40バイトヘッダー + JPEG）
- カメラフレームをデバイス上でYUV420→JPEG変換（Isolate）してサーバーに送信
- ピンポン方式のフロー制御（サーバー応答後に次フレーム送信）
- mDNS（Bonjour）によるサーバー自動検出

### Phase 2: SD1.5 + LCM img2img 変換
- `SimianLuo/LCM_Dreamshaper_v7` を `AutoPipelineForImage2Image` でロード
- Apple Silicon MPS 対応（M4 Max で約1秒/フレーム）
- NSFW safety checker 無効化（カメラ映像の誤検知対策）
- `asyncio.run_in_executor` で推論をスレッドプールに逃がし、イベントループのブロックを回避

### Phase 3: ハイブリッドアーキテクチャへの移行
- **プレビュー**: CIFilter（iOS Core Image）によるリアルタイムフィルタ（セピア、白黒、色褪せなど）
- **シャッター**: サーバーの SD img2img で高品質変換（768x768、20ステップ）
- Before/After 比較スライダー、カメラロール保存、共有機能
- CoreMLスタイル転送も試したが、入力画像と無関係な出力になったため CIFilter に置き換え

---

## わかったこと

### 技術的な知見

| 知見 | 詳細 |
|---|---|
| **リアルタイム動画変換は現行技術では無理** | SD img2img は M4 Max MPS で1フレーム約1秒。フレーム間の連続性がなく「パラパラ漫画」になる。strength を下げてもテンポラルブレンドを入れても、動画として自然に見えるレベルにはならない |
| **CIFilter は即座に使えて実用的** | セピア/白黒/色褪せフィルタはCore Image で60fps。「雰囲気」レベルなら十分 |
| **iOS ローカルネットワーク制限が厄介** | Flutter の dart:io ソケットは iOS のローカルネットワークで「No route to host」になる。Safari（NSURLSession）は通る。解決策は起動時に WebSocket を張って維持し、全通信をその上で行うこと |
| **CoreML スタイル転送は「画風」であって「時代」ではない** | Magenta のスタイル転送モデルは画家の画風を移すもの。「大正時代の写真っぽさ」は表現できない |
| **`DiffusionPipeline` と `AutoPipelineForImage2Image` は別物** | 前者は text-to-image をロードし、image パラメータを無視する。img2img には後者が必須 |

### プロダクトとしての知見

| 知見 | 詳細 |
|---|---|
| **「見た目を昔っぽくする」だけだとフィルターアプリ止まり** | 数回使って飽きる。差別化が弱い |
| **位置情報 × 古写真は面白いがデータが存在しない** | 日本の古写真DB（長崎大学 約8,800枚、東京大学 約7,000枚）には緯度経度がない。GPS以前の写真なので当然。全国カバーには程遠い |
| **AI推定で「過去の風景」を生成するのは嘘になる** | LLM + SD で「ここは江戸時代は宿場町でした」と画像を作れるが、その場所の過去ではなく「宿場町っぽい絵」でしかない |
| **体験とラグのトレードオフ** | 写真1枚変換は待ち時間が体験を壊す。動画変換は連続性がない。「プレビューは軽量フィルタ、シャッターで本気変換」のハイブリッドが現実的な落とし所 |

---

## アーキテクチャ（最終形）

```
┌─ iPhone ─────────────────────────────────────────┐
│                                                   │
│  Camera 30fps                                     │
│    → 3フレームに1回 JPEG変換 (Isolate)             │
│    → CIFilter (セピア/白黒/色褪せ) → 画面表示      │
│                                                   │
│  [シャッター]                                      │
│    → 既存WebSocket接続で JPEG + era_id を送信      │
│    → サーバー SD1.5 img2img 変換 (3-5秒)           │
│    → ResultPage: Before/After比較 → 保存/共有      │
│                                                   │
│  mDNS自動検出 / 手動IP入力                         │
└───────┬───────────────────────────────────────────┘
        │ WebSocket (常時接続)
┌───────▼───────────────────────────────────────────┐
│  Python FastAPI Server                             │
│                                                   │
│  WebSocket /stream  ← フレームストリーム + capture  │
│  SD1.5 + LCM img2img (AutoPipelineForImage2Image)  │
│  MPS (Apple Silicon) / CUDA 対応                    │
└───────────────────────────────────────────────────┘
```

## 技術スタック

| レイヤー | 技術 |
|---|---|
| モバイル | Flutter, camera plugin, CIFilter (Swift Platform Channel), web_socket_channel |
| サーバー | Python, FastAPI, uvicorn, diffusers (SD1.5 + LCM), zeroconf (mDNS) |
| AI | Stable Diffusion 1.5, Latent Consistency Models, ControlNet (実装済み未検証) |
| インフラ | uv (Python), fvm (Flutter), Docker (GPU用) |

## セットアップ

### サーバー

```bash
cd server
uv sync --extra mps     # Apple Silicon
# or
uv sync --extra gpu     # NVIDIA GPU

PIPELINE=lcm uv run uvicorn src.chrono_lens_server.main:app --host 0.0.0.0 --port 8765
```

### モバイル

```bash
cd mobile
fvm flutter pub get
fvm flutter run
```

## ライセンス

検証目的のプロジェクト。
