# chrono-lens

「今ある技術で、なるべくリアルタイムに過去の風景を映す」実験的カメラアプリ

## 概要

スマートフォンのカメラ映像をリアルタイムでAI変換し、現在の風景を「大正時代」や「昭和初期」などの過去の風景に変換して表示する実験的なプロジェクト。

## アーキテクチャ

```
Flutter (Mobile) <--WebSocket--> Python GPU Server
     |                                  |
  Camera Stream               SD1.5 + LCM + ControlNet
  Frame Compression           (4-8 steps / 100-200ms)
  CrossFade Rendering         ControlNet Depth/Canny
```

## 技術スタック

### モバイル (Flutter)
- カメラストリーム取得 (`camera` plugin)
- デバイス側リサイズ・圧縮 (512x512px JPEG)
- FPS制御 (4-5 FPS)
- WebSocketストリーミング
- クロスフェード描画

### サーバー (Python)
- FastAPI + WebSocket
- Stable Diffusion 1.5 + LCM (4-8 steps)
- ControlNet (Depth / Canny)
- フリッカー対策 (Seed固定 / Color Fix)

## 開発フェーズ

1. **Phase 1**: WebSocketストリーミングモック（AI無し）
   - Flutter ↔ Python間のカメラ映像往復のベースライン計測
2. **Phase 2**: SD1.5 + LCM 推論パイプライン構築
3. **Phase 3**: ControlNet統合
4. **Phase 4**: フリッカー対策・UX改善

## セットアップ・起動手順

### サーバー

```bash
cd server

# Phase 1 (GPU不要)
uv sync

# Phase 2以降 (CUDA必須)
uv sync --extra gpu
uv pip install torch --index-url https://download.pytorch.org/whl/cu121

# 起動
# PIPELINE=echo     → Phase 1（AI無し、デフォルト）
# PIPELINE=lcm      → Phase 2（SD1.5 + LCM）
# PIPELINE=controlnet → Phase 3（ControlNet）
uv run uvicorn src.chrono_lens_server.main:app --host 0.0.0.0 --port 8765

# または Docker (GPU環境)
docker compose -f docker/docker-compose.yml up
```

テスト実行:
```bash
cd server
uv sync --extra dev
uv run pytest
```

### モバイル (Flutter)

```bash
# fvm が未インストールの場合
brew tap leoafarias/fvm && brew install fvm
fvm install stable

cd mobile
fvm flutter pub get
fvm flutter run          # 接続したiPhoneに転送
```

初回起動時にIP入力画面が表示されます。PCのIPとポート8765を入力してください。
