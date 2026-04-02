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
