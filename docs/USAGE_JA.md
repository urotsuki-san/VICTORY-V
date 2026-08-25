# VICTORY-V 日本語ガイド

## 現在の状態

このリポジトリは、Tang Nano 20Kへ載せる直前までの**研究用プロトタイプ**です。

現時点で入っているものは次のとおりです。

- `VV32-A0`命令仕様
- アセンブラ／逆アセンブラ
- PC上で動く参照エミュレータ
- Capability境界・権限検査
- Secret Tagの伝播と秘密依存分岐／アドレスの拒否
- `VTRY`／`VCHK`／`VIC`／`VABT`による書き込み保留・確定・破棄
- SystemVerilog版CPUコア
- RTLテストベンチ
- 初期形式検証ハーネス
- GitHub Actions

実機用のピン設定、PLL、UART SoC、Gowinプロジェクト、bitstreamはまだありません。

## セットアップ

Python 3.11以上を使用します。実行時の外部Pythonライブラリはありません。

```bash
git clone https://github.com/urotsuki-san/VICTORY-V.git
cd VICTORY-V
python -m pip install -e . --no-build-isolation
```

## アセンブル

```bash
vv asm examples/victory.vs -o build/victory.vbin
```

アドレス・機械語・逆アセンブル結果を並べたリストも出せます。

```bash
vv asm examples/victory.vs \
  -o build/victory.vbin \
  --listing build/victory.lst
```

## PC上で実行

```bash
vv run examples/victory.vs --trace --registers
```

正常例では最後に概ね次のように表示されます。

```text
status=HALT pc=0x00000048 cause=0 victory_error=0
```

失敗を握りつぶして勝利扱いにする仕様ではありません。`VCHK`やCapability検査に失敗した場合、書き込みを破棄して失敗経路へ移動し、`VERR`で理由を取得します。

## テスト

```bash
make test
make examples
python tools/check_isa_sync.py
```

Icarus Verilogが入っている環境ではRTLも確認できます。

```bash
make rtl-test
```

## FPGAを買う時期

最初に必要なのはTang Nano 20Kを1枚だけです。ただし、[`FPGA_HANDOFF.md`](FPGA_HANDOFF.md)の未完了項目が残っている間は、ボードがなくても開発を進められます。

当面の作業は、参照モデルとRTLが同じ命令列で同じ状態になることを自動比較する工程です。

## 注意

このCPUは研究用です。実データの保護、車載・医療・産業制御、暗号鍵管理などへ使用してはいけません。テスト合格はセキュリティ証明ではありません。
