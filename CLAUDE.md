# picture-filter プロジェクトメモ

## 概要
画像フィルタ確認用のシングルページWebアプリ（`index.html` 1ファイル完結）。

## パネル構成（6分割）
| idx | タイトル | パラメータ |
|-----|---------|-----------|
| 0 | Original | なし |
| 1 | Grayscale | なし |
| 2 | Binary | Threshold スライダー |
| 3 | Edge (Sobel) | Threshold スライダー |
| 4 | Blur | Type セレクト + Radius スライダー |
| 5 | Reduce Color | Colors スライダー（k-means） |

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

### レンダリング分離
- `renderAll()` — フィルタ再計算 + 描画（スライダー変更・ズームレベル変化時）
- `renderView()` — キャッシュ済みフィルタから再描画のみ（パン・アノテーション描画中）
- フィルタキャッシュは `filterResults[6]` に保持、パラメータ変更時に `invalidateFilter(idx)` で個別無効化

### 座標系
- アノテーションは画像座標系で保存（ズーム・パンに追従）
- 左右反転（Flip H）時は `screenToImage`、`applyZoom`、ホイールズーム、パンの全箇所でX座標を補正済み

## ツール
- Pan / Zoom / Line / Freehand
- Zoom: 通常クリック=拡大、Alt/Option+クリック=縮小、Space長押し=一時Pan
- Flip H: 全パネル同期で左右反転トグル

## デプロイ
- GitHub Pages、Source は **GitHub Actions** に設定
- `main` push で自動デプロイ
