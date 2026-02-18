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
- 左右反転（Flip H）時は `screenToImage`、`applyZoom`、ホイールズーム、パンの全箇所でX座標を補正済み

### アノテーション管理
- `annotations`: 確定済みストロークの配列 `{type:'line'|'free', points:[[x,y],...], color, width}`
- `drawState`: 描画中ストローク（確定前）。`annotationsVisible` が false でも常に表示
- **Hide Annot. ボタン**: `annotationsVisible` フラグをトグル。`renderView()` のみ呼ぶのでフィルタ再計算なし

### 消しゴム（Erase ツール）
- ストローク単位で削除。クリックまたはドラッグで最近傍ストロークを消去
- `eraseAnnotationAt(ix, iy)`: 画像座標でヒット判定し、最近傍ストロークを `annotations.splice` で削除
- `pointToSegmentDist`: 点と線分の最短距離（パラメトリック投影）
- ヒット許容範囲: `ストロークの width / 2 / view.scale + 8 / view.scale`（8スクリーンピクセルのバッファ）
- `isErasing` フラグで drag-erase（移動中も連続削除）を実現

## ツール
- Pan / Zoom / Line / Freehand / Erase
- Zoom: 通常クリック=拡大、Alt/Option+クリック=縮小、Space長押し=一時Pan
- Flip H: 全パネル同期で左右反転トグル
- Hide Annot.: アノテーションの表示/非表示トグル（ストロークは保持）

## デプロイ
- GitHub Pages、Source は **GitHub Actions** に設定
- `main` push で自動デプロイ
