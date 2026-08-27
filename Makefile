PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp

.PHONY: install test examples family-check fpga-rom fpga-check fpga-handoff-check docs-check rtl-test rtl-test-vv32 rtl-test-vv64 rtl-test-contract-vv32 rtl-test-contract-vv64 rtl-test-region-irq rtl-test-vrtu rtl-test-dual rtl-test-cluster experiment-euclid check clean

install:
	$(PYTHON) -m pip install -e .

test:
	PYTHONPATH=src $(PYTHON) -m unittest discover -s tests -v

examples:
	mkdir -p build
	PYTHONPATH=src $(PYTHON) -m victory_v.cli asm examples/victory.vs -o build/victory.vbin
	PYTHONPATH=src $(PYTHON) -m victory_v.cli run examples/victory.vs
	PYTHONPATH=src $(PYTHON) -m victory_v.cli run examples/rollback.vs
	PYTHONPATH=src $(PYTHON) -m victory_v.cli run examples/capability_fault.vs
	PYTHONPATH=src $(PYTHON) -m victory_v.cli run examples/secret_flow.vs
	PYTHONPATH=src $(PYTHON) -m victory_v.cli profiles

family-check:
	PYTHONPATH=src $(PYTHON) tools/check_family_manifest.py

fpga-rom:
	$(PYTHON) tools/gen_fpga_bringup.py

fpga-check:
	$(PYTHON) tools/check_fpga_bringup.py

fpga-handoff-check:
	$(PYTHON) tools/check_fpga_handoff.py

docs-check:
	$(PYTHON) tools/check_docs_sync.py

rtl-test-vv32:
	mkdir -p rtl/build
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Irtl -s vv32_core_tb -o rtl/build/vv32_core_tb.vvp \
		rtl/vv32_pkg.sv rtl/vv32_core.sv rtl/tb/vv32_core_tb.sv
	$(VVP) rtl/build/vv32_core_tb.vvp

rtl-test-vv64:
	mkdir -p rtl/build
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Irtl -s vv64_core_tb -o rtl/build/vv64_core_tb.vvp \
		rtl/vv64_pkg.sv rtl/vv64_core.sv rtl/tb/vv64_core_tb.sv
	$(VVP) rtl/build/vv64_core_tb.vvp


rtl-test-contract-vv32:
	mkdir -p rtl/build
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Irtl -s vv32_contract_tb -o rtl/build/vv32_contract_tb.vvp \
		rtl/vv32_pkg.sv rtl/vv32_core.sv rtl/tb/vv32_contract_tb.sv
	$(VVP) rtl/build/vv32_contract_tb.vvp

rtl-test-contract-vv64:
	mkdir -p rtl/build
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Irtl -s vv64_contract_tb -o rtl/build/vv64_contract_tb.vvp \
		rtl/vv64_pkg.sv rtl/vv64_core.sv rtl/tb/vv64_contract_tb.sv
	$(VVP) rtl/build/vv64_contract_tb.vvp

rtl-test-region-irq:
	mkdir -p rtl/build
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Irtl -s vv32_region_irq_tb -o rtl/build/vv32_region_irq_tb.vvp \
		rtl/vv32_pkg.sv rtl/vv32_core.sv rtl/tb/vv32_region_irq_tb.sv
	$(VVP) rtl/build/vv32_region_irq_tb.vvp

rtl-test-vrtu:
	mkdir -p rtl/build
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Irtl -s vv_vrtu_tb -o rtl/build/vv_vrtu_tb.vvp \
		rtl/memory/vv_vrtu.sv rtl/tb/vv_vrtu_tb.sv
	$(VVP) rtl/build/vv_vrtu_tb.vvp

rtl-test-dual:
	mkdir -p rtl/build
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Irtl -s vv_dual_bringup_tb -o rtl/build/vv_dual_bringup_tb.vvp \
		rtl/vv32_pkg.sv rtl/vv32_core.sv \
		rtl/vv64_pkg.sv rtl/vv64_core.sv \
		rtl/common/vv_uart_tx.sv rtl/common/vv_sram.sv \
		rtl/boot/vv_bringup_rom.sv rtl/soc/vv_dual_bringup.sv \
		rtl/tb/vv_dual_bringup_tb.sv
	$(VVP) rtl/build/vv_dual_bringup_tb.vvp

rtl-test-cluster:
	mkdir -p rtl/build
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Irtl -s vv_cluster_bringup_tb -o rtl/build/vv_cluster_bringup_tb.vvp \
		rtl/vv32_pkg.sv rtl/vv32_core.sv \
		rtl/vv64_pkg.sv rtl/vv64_core.sv rtl/memory/vv_vrtu.sv rtl/vv64_profiled_core.sv \
		rtl/common/vv_uart_tx.sv rtl/common/vv_sram.sv \
		rtl/boot/vv_bringup_rom.sv rtl/soc/vv_cluster_bringup.sv \
		rtl/tb/vv_cluster_bringup_tb.sv
	$(VVP) rtl/build/vv_cluster_bringup_tb.vvp

experiment-euclid:
	mkdir -p rtl/build
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Irtl -s vv_euclid_a0_tb -o rtl/build/vv_euclid_a0_tb.vvp \
		experiments/euclid/rtl/vv_euclid_a0.sv experiments/euclid/tb/vv_euclid_a0_tb.sv
	$(VVP) rtl/build/vv_euclid_a0_tb.vvp
	PYTHONPATH=src $(PYTHON) -m unittest -v experiments/euclid/test_euclid.py

rtl-test: rtl-test-vv32 rtl-test-vv64 rtl-test-contract-vv32 rtl-test-contract-vv64 rtl-test-region-irq rtl-test-vrtu rtl-test-dual rtl-test-cluster

check: test examples family-check fpga-check fpga-handoff-check docs-check rtl-test
	PYTHONPATH=src $(PYTHON) tools/check_isa_sync.py

clean:
	rm -rf build rtl/build src/*.egg-info
	find src tests tools experiments -type d -name __pycache__ -prune -exec rm -rf {} +
