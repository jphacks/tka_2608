# 紹介プレゼンの素材

ルートの `final.marp` 用。発表日は2026.10.18、チーム名は「あと1分だけ」。アプリ名を新しく決定した資料ではありません。

- `ant-character.png`: 今回ユーザーが添付したキャラクターのPNG。元ファイルをそのままコピーし、透明背景を保持。
- `figma-chat.png`: [指定Figmaのチャット画面「やることを選んだあと」（72:286）](https://www.figma.com/design/48CTZsdZVoKdV87ZnlYQin/JPhack?node-id=72-286)。2026-10-17にFigmaツールで取得。元画像の比率と内容を維持。

Figma画面の会話・数値はデザイン上の表示例です。マイクボタンなど、現在の実装範囲とは異なる表示も原本のまま含みます。スライド左側の声かけは今回の説明用の会話例です。

## プレビュー・書き出し

Marp CLIが必要です。HTMLレイアウトを含むため `--html`、ローカル画像を含むPDF・PNG出力には `--allow-local-files` を指定します。ルートディレクトリで実行してください。

```sh
marp final.marp --html --output final.html
marp final.marp --html --pdf --allow-local-files --output final.pdf
marp final.marp --html --images png --allow-local-files --output final.png
```

PNGは `final.001.png` と `final.002.png` に出力されます。PDF・PNG書き出しには対応ブラウザーも必要です。
