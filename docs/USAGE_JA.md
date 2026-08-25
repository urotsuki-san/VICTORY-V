# VICTORY-V 日本語ガイド

## 現在地

動いているのは32ビットの`VV32-A0`です。アセンブラ、逆アセンブラ、Python参照モデル、SystemVerilogコア、テストベンチまで入っています。FPGA用bitstreamはまだありません。

64ビットの`VV64-A0`は別のCPUへ乗り換える計画ではありません。Capability、Secret Tag、Victory Region、`VLOCK`、非投機の基本方針を`VV32-A0`から継承し、Linuxに必要な特権、Atomic、Context保存、任意のMMUを追加します。

```text
VV32-A0          実装中。小型FPGA向け
VV64-A0          設計中。ネイティブ64ビットVICTORY-V
VV64-L0/flat     MMUなしLinux。最初のLinux目標
VV64-L0/paged    V39 MMUありLinux。その次
```

Linuxを別のRISC-Vコアで動かす話ではありません。

## セットアップ

```bash
git clone https://github.com/urotsuki-san/VICTORY-V.git
cd VICTORY-V
python -m pip install -e .
vv profiles
```

## VV32-A0を動かす

```bash
vv asm examples/victory.vs -o build/victory.vbin
vv run examples/victory.vs --trace --registers
```

Victory Region内の書き込みは`VIC`まで外へ出ません。Capability違反、Secret Flow違反、`VCHK`失敗、Store数超過、命令数超過が起きると、書き込みを捨てて失敗先へ移ります。

## テスト

```bash
make test
make examples
make family-check
make rtl-test       # Icarus Verilogが必要
```

## FPGA

`VV32-A0`の最初の対象はTang Nano 20Kです。ここは小型CPUとして完成させます。

`VV64-A0`はTang Console 138Kを対象にします。順番は、On-chip RAMとUART、割り込み、Tagged Context、DDR3、MMUなしLinux、最後にV39 MMUです。

LiteXを使う場合も、利用するのはBoard定義やDDR周りです。CPU本体とISAはVICTORY-Vです。

## まだできないこと

- FPGA実機起動
- C/C++コンパイル
- 64ビット命令の実行
- Linux起動
- Capabilityを保ったTask切り替え

設計中の機能と実装済みの機能はREADMEの表で分けています。
