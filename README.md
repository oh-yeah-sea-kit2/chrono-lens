# chrono-lens

「目の前の風景を昔っぽく見せる」実験的カメラアプリ

## 概要

スマートフォンのカメラをかざすと、リアルタイムのスタイル転送で風景が「大正時代」「昭和初期」風に見えるプレビューを表示。シャッターを押すとサーバーのStable Diffusionで高品質な時代変換画像を生成し、Before/After比較で確認・保存できます。

## アーキテクチャ

```
┌─ iPhone ──────────────────────────────────────┐
│ Camera 30fps → CoreML Style Transfer → Preview │
│                                                │
│ [Shutter] → HTTP POST ────────────────────┐    │
│ ← Result ← Before/After ← Save/Share     │    │
└───────────────────────────────────────────┘    │
                                                 │
               ┌─ Python Server ─────────────────▼─┐
               │ POST /capture                      │
               │ SD1.5 + LCM img2img (768x768)      │
               │ 3-5秒で高品質変換                   │
               └────────────────────────────────────┘
```

## セットアップ

### サーバー

```bash
cd server

# Apple Silicon (M1/M2/M3/M4)
uv sync --extra mps

# NVIDIA GPU
uv sync --extra gpu
uv pip install torch --index-url https://download.pytorch.org/whl/cu121

# 起動
PIPELINE=lcm uv run uvicorn src.chrono_lens_server.main:app --host 0.0.0.0 --port 8765
```

### CoreML モデル変換

```bash
pip install -r tools/requirements.txt
python tools/convert_style_model.py
# → tools/output/ の .mlpackage を mobile/ios/Runner/Models/ にコピー
```

### モバイル

```bash
brew tap leoafarias/fvm && brew install fvm
fvm install stable

cd mobile
fvm flutter pub get
fvm flutter run
```

アプリ起動時にサーバーが自動検出されます（mDNS）。見つからない場合は手動でIPを入力。

## 対応時代

| 時代 | 特徴 |
|---|---|
| 大正（1912–1926）| セピア調、手彩色写真風 |
| 昭和初期（1926–1945）| 高コントラスト白黒 |
| 昭和中期（1945–1970）| 色褪せたKodachrome風 |
| 明治（1868–1912）| 銀塩プリント、強ビネット |
