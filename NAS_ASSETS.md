# NAS に退避した作業データ

Git で管理していない重いファイル（画像・動画・モデル・出力など）は、自宅 NAS に置いてある。
このリポジトリを clone しただけでは入らないので、必要になったら下の手順で戻す。

- 退避日: 2026-10-01
- 置き場所: `/Volumes/Public/開発アーカイブ/projects/chrono-lens/`
  （NAS: QNAP TS-231K `//oh-yeah-sea-kit2@NAS4D732E._smb._tcp.local/Public`）
- 1MB以上のファイル: 2 件 / 47.6MB。リポジトリと同じフォルダ構成のまま置いてある（NAS 上でそのまま開ける）
- 1MB未満のファイル: 29 件 / 0.1MB。`small_files.tar` に1つにまとめてある（件数が多く、SMB で1件ずつ送ると遅いため）
- ファイル一覧とハッシュ: `nas_assets_manifest.sha256`（sha256）

## 戻し方

```bash
# 1. NAS をマウントする（Finder で接続するか、次の1行）
osascript -e 'mount volume "smb://oh-yeah-sea-kit2@NAS4D732E._smb._tcp.local/Public"'

# 2. リポジトリのルートで実行する
N="/Volumes/Public/開発アーカイブ/projects/chrono-lens"
rsync -a --exclude small_files.tar --exclude 'nas_assets_manifest_full.sha256' "$N/" ./   # 1MB以上
tar -xf "$N/small_files.tar"                                                              # 1MB未満

# 3. 壊れていないか確かめる（何も表示されなければ全件一致）
shasum -a 256 -c nas_assets_manifest.sha256 | grep -v ': OK$'
```

## 退避したもの（上位）

| フォルダ | ファイル数 | 容量 |
|---|---|---|
| `tools/` | 3 | 47.6MB |
| `mobile/` | 27 | 0.1MB |
| `.DS_Store` | 1 | 0.0MB |

## 退避せずに消したもの（作り直せる）

- `mobile/ios/Pods/`
- `server/.venv/`
- `tools/.venv/`

`.venv` は `uv sync`／`uv venv`、`node_modules` は `npm install`、Unity の `Library` と Unreal の `Intermediate`・`DerivedDataCache`・Godot の `.godot` はエディタで開くと再生成される。
