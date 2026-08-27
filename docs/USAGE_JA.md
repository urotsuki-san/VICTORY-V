# VICTORY-V 使用メモ

## 現在の構成

```text
VV32-A0       監視・制御
VV64-P0       主コア + 4エントリ VRTU
VV64-E0       小型コア + 2エントリ VRTU
```

標準のTang 138KイメージにEuclidコアは入りません。旧コードは`experiments/euclid/`へ隔離されています。

## VTRYとVictory Region

Regionを始める命令は`VTRY`です。オペランド数で二つの符号化を選びます。

```text
VTRY fail, stores, budget   小さな契約をその場で宣言して開始する
VPREP cToken, cArena, rSpec 詳細な契約を事前審査する
VTRY cToken, fail           準備済みトークンを消費して開始する
VCANCEL cToken              使わないトークンを失効させる
```

仕様上の呼び分けは`VTRY.I`と`VTRY.C`です。アセンブラはどちらも`vtry`で受け付け、明示したい場合だけ`vtry.c`も使えます。`VPREP`は審査だけを行い、Regionは開始しません。

Tang 138KのROMは、各コアで直接`VTRY`のcommit、準備済み`VTRY`のcommit、abortによるrollbackを確認してから`VTRY ready`を出します。P0/E0はRegionからMMIOへ書けないことも確認します。

## 検査

```bash
python -m pip install -e .
make test
make examples
make family-check
make fpga-check
make fpga-handoff-check
make docs-check
make rtl-test
```

Icarus Verilogがない環境では、Pythonと静的検査だけを先に実行できます。

## VRTU

VRTUは少数の連続範囲を正確に変換・保護します。

```text
一致なし      cause 20
権限不足      cause 21
複数範囲一致  cause 22
```

ソフトウェアTLB補充もページテーブルウォーカーもありません。初期状態ではRAMとMMIOを恒等変換し、P0/E0の命令・データアクセスを検査します。Region中のMMIOはdevice faultになります。

## FPGA

実機では基板とB/Cリビジョンに合う`.gprj`を開き、50 MHz制約で合成と配置配線を行います。期待するUARTは次の3行です。

```text
VV32-A0 VTRY ready
VV64-P0 VTRY ready
VV64-E0 VTRY ready
```

合成結果、Fmax、LUT/FF/BSRAM、UART実測が揃うまでは実機成功とは扱いません。
