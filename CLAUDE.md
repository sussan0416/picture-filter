# picture-filter プロジェクトメモ

## 概要
画像フィルタ確認用のシングルページWebアプリ（`index.html` 1ファイル完結）。

## パネル構成（6分割）
| idx | タイトル | パラメータ |
|-----|---------|-----------|
| 0 | Original | Brightness スライダー / Contrast スライダー |
| 1 | Grayscale | Brightness スライダー / Contrast スライダー |
| 2 | Binary | Threshold スライダー |
| 3 | Edge (Sobel) | Threshold スライダー |
| 4 | Blur | Type セレクト + Radius スライダー |
| 5 | Reduce Color | Colors スライダー（k-means） |

各パネルヘッダー右端に **↺（パラメータリセット）** と **⛶（単体表示）** ボタンがある。

## OpenCV.js
- ローカルに `opencv.js` を置いて使う（gitignore済み）
- GitHub Pages デプロイ時に `.github/workflows/deploy.yml` が最新リリースから自動ダウンロード
  - `https://github.com/opencv/opencv/releases` の最新タグを取得
  - `opencv-{version}-docs.zip` をDL → `js/bin/opencv.js` だけ展開 → zip削除
- ライセンス: Apache 2.0。ページ内にOpenCVリポジトリへのリンクを表示することで表示義務を満たす
- OpenCV未ロード時は**全フィルタ**がJSフォールバックで動作する（ロード完了時に全フィルタ + 作業データを再計算）

### フィルタの OpenCV 実装
| フィルタ | CV 実装 | JS fallback |
|---------|---------|------------|
| Grayscale | `cv.cvtColor(RGBA2GRAY)` | workingGray ループ |
| Binary | `cv.cvtColor` + `cv.threshold` | workingGray ループ |
| Edge/Sobel | `cv.Sobel(CV_32F)` + `cv.magnitude` | JS ネストループ |
| Blur | `cv.blur/GaussianBlur/medianBlur/bilateralFilter` | JS Gaussian |
| Reduce Color | `cv.kmeans`（全ピクセル、k-means++） | JS k-means（サブサンプリング付き） |

- Mat のメモリ解放は全て `try...finally` パターンで保証

## アーキテクチャのポイント

### Working Resolution（ミップレベル）
- フィルタはフル解像度ではなく、表示ズームに合わせたダウンサンプル解像度で処理
- 離散ミップレベル: 1, 0.5, 0.25, 0.125
- ミップレベルをまたぐズーム時のみフィルタを再計算

### 前処理（`ensureWorkingData`）
- **mip < 1 かつ cvReady**: `cv.resize(INTER_AREA)` でダウンサンプル（ブラウザ bilinear より高品質な面積平均法）＋ `cv.cvtColor` でグレースケール抽出、1パスで完了
- **mip === 1 または CV 未ロード**: `canvas.drawImage()`（GPU リサンプリング）＋ JS 輝度ループ
- 結果を `workingCanvas`（RGBA）と `workingGray`（Uint8Array）にキャッシュ
- グレースケールは Grayscale / Binary / Edge フィルタの JS fallback が共用

### Brightness / Contrast（`applyBCToCanvas`）
- panel 0（Original）と panel 1（Grayscale）に適用
- `panelBC[0/1] = { brightness: -100〜100, contrast: -100〜100 }`
- OpenCV: `Mat.convertTo(dst, -1, alpha, beta)`（alpha = 1 + contrast/100、beta = brightness）
- JS fallback: ピクセルループで `clamp(alpha * v + beta, 0, 255)`
- B/C が両方 0 の場合は srcCanvas をそのまま返してコピーをスキップ
- `getFilterKey(0/1)` に B/C 値を含めてキャッシュを管理
- panel 0 は以前 `ensureFilter` で早期 return していたが、B/C 対応のため通常フィルタと同じパスで処理

### レンダリング分離
- `renderAll()` — フィルタ再計算 + 描画（スライダー変更・ズームレベル変化時）
- `renderView()` — キャッシュ済みフィルタから再描画のみ（パン・アノテーション描画中）
- フィルタキャッシュは `filterResults[6]` に保持、パラメータ変更時に `invalidateFilter(idx)` で個別無効化

### 単体表示（Solo view）
- `soloPanel`（null or 0〜5）で状態管理
- `enterSolo(idx)` / `exitSolo()` で切り替え
- CSS: `#grid.solo .panel:not(.solo-active) { display: none }` + `grid-column: 1/4; grid-row: 1/3` でフル展開
- 切り替え時に `resizeCanvases()` → `resetView()` → `renderAll()` の順で呼び出し、キャンバスリサイズ後に自動 Fit Image

### Fit Image（旧 Reset View）
- `resetView()` は常に表示中のパネルサイズを基準にする
- ソロモード中: `panels[soloPanel]` のサイズを使用（panel 0 が非表示で getBoundingClientRect() = 0×0 になるため）
- グリッド表示中: `panels[0]` のサイズを使用

### パラメータリセット
- `PANEL_DEFAULTS[idx]()` が各パネルのデフォルト値に戻す関数
- デフォルト値: Brightness/Contrast=0、Binary threshold=128、Edge threshold=30、Blur type=gaussian/radius=3、Colors=8

### 座標系
- アノテーションは画像座標系で保存（ズーム・パンに追従）
- 左右反転（Mirror）時は `screenToImage`、`applyZoom`、ホイールズーム、パンの全箇所でX座標を補正済み

### アノテーション管理
- `annotations`: 確定済みストロークの配列 `{type:'line'|'free'|'oval', points:[[x,y],...], color, width}`
- `drawState`: 描画中ストローク（確定前）。`annotationsVisible` が false でも常に表示
- **Hide/Show ボタン**: `annotationsVisible` フラグをトグル。`renderView()` のみ呼ぶのでフィルタ再計算なし。ボタン幅は `min-width: 4.5em` で固定

### 消しゴム（Erase ツール）
- ストローク単位で削除。クリックまたはドラッグで最近傍ストロークを消去
- `eraseAnnotationAt(ix, iy)`: 画像座標でヒット判定し、最近傍ストロークを `annotations.splice` で削除
- `pointToSegmentDist`: 点と線分の最短距離（パラメトリック投影）
- ヒット許容範囲: `ストロークの width / 2 / view.scale + 8 / view.scale`（8スクリーンピクセルのバッファ）
- `isErasing` フラグで drag-erase（移動中も連続削除）を実現
- Oval のヒット判定: `atan2` で楕円輪郭上の最近傍点を求めて距離を計算

### Oval ツール
- ドラッグの始点・終点をバウンディングボックスの対角コーナーとして楕円を描画
- `points[0]`（ドラッグ開始）と `points[1]`（ドラッグ終了）の2点で管理（Line と同じ2点モデル）
- `drawAnnotation` 内で `cx/cy/rx/ry` を算出し `ctx.ellipse()` で描画
- rx または ry が 0 の場合（タップのみ）は描画スキップ

### タッチ操作（ピンチズーム）
- `.panel canvas` に `touch-action: none` を設定してブラウザデフォルトのピンチ拡大を無効化
- 各キャンバスのイベントループ内に `ptrMap`（`Map<pointerId, {x,y}>`）を保持してアクティブポインターを追跡
- `pointerdown` 時に `ptrMap.size >= 2` を検出したらパン/描画/消しゴムをキャンセルしてピンチモードへ移行
- `pointermove` 時に2点間距離の変化率でスケール計算、2本指の中点を基準にズーム
- `pointercancel` ハンドラーで電話着信などの割り込み時に状態をリセット
- ピンチ終了後（指を全て離した後）に単指操作を再開するには新たな `pointerdown` が必要

## ツール
- Pan / Zoom / Line / Freehand / Oval / Measure / Erase
- Zoom: 通常クリック=拡大、Alt/Option+クリック=縮小、Space長押し=一時Pan
- タッチ: 2本指ピンチで拡大縮小
- Mirror: 全パネル同期で左右反転トグル
- Hide/Show: アノテーションの表示/非表示トグル（ストロークは保持）
- Clear: 全アノテーション削除

### Measure ツール（2フェーズ操作）
- **Phase 1（準備）**: ドラッグで基準線を引く。pointerup で確定（基準長さが決まる）
- **Phase 2（確定）**: マウス移動でリアルタイムプレビュー。pointerup でクリックした位置まで線を延ばして確定
- 確定時、基準線の長さ間隔ごとに直交するティックマーク（10スクリーンpx）を描画
- Phase 1 + Phase 2 が1つのアノテーション = 1回の Undo でまとめて取り消し可能
- Phase 2 プレビュー中にツールを切り替え or Undo を押すとキャンセル
- 保存形式: `{ type:'measure', points:[refStart, refEnd, extEnd], color, width }`
  - `points[0]`: 基準線の始点、`points[1]`: 基準線の終点（= 基準長さの端）、`points[2]`: 延長先
- `drawMeasureAnnotation`: ティックマーク長 = `10 / view.scale`（image coords）= 常に20スクリーンpx
- 始点（refStart）と終点（refEnd）にも直交線を描画
  - Phase 1 プレビュー: AB 方向に対して垂直
  - Phase 2: AC 方向（メインライン方向）に対して垂直。interval ティックのみ（実際の B 位置には描画しない）
- **bidirectional モード**: Phase 2 確定時に Option/Alt を押しながら pointerup → 始点から逆方向にも同じ長さで線・ティックを延長
  - `bidirectional: true` フラグをアノテーションに保存
  - Phase 2 pointermove でも `altHeld` によりリアルタイムプレビュー更新
  - Erase ヒット判定: bidirectional 時は逆端（`2*ax - cx`）→ extEnd の線分
- Erase ヒット判定: `points[0]` → `points[2]` の線分に対して距離計算（非 bidirectional）

### Oval ツール — fromCenter モード
- Option/Alt キーを押しながら pointerdown を開始すると、ドラッグ始点が楕円の**中心**になる
- `fromCenter: true` フラグをアノテーションに保存
- 描画: `cx/cy = points[0]`, `rx = |points[1].x - points[0].x|`, `ry = |points[1].y - points[0].y|`（通常モードの 2 倍の半径）
- Erase ヒット判定も fromCenter フラグを考慮

## デプロイ
- GitHub Pages、Source は **GitHub Actions** に設定
- `main` push で自動デプロイ
