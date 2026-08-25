PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp

.PHONY: install test examples rtl-test check clean

install:
	$(PYTHON) -m pip install -e . --no-build-isolation

test:
	PYTHONPATH=src $(PYTHON) -m unittest discover -s tests -v

examples:
	mkdir -p build
	PYTHONPATH=src $(PYTHON) -m victory_v.cli asm examples/victory.vs -o build/victory.vbin
	PYTHONPATH=src $(PYTHON) -m victory_v.cli run examples/victory.vs
	PYTHONPATH=src $(PYTHON) -m victory_v.cli run examples/rollback.vs
	PYTHONPATH=src $(PYTHON) -m victory_v.cli run examples/capability_fault.vs
	PYTHONPATH=src $(PYTHON) -m victory_v.cli run examples/secret_flow.vs

rtl-test:
	mkdir -p rtl/build
	$(IVERILOG) -g2012 -Wall -Wno-timescale -Irtl -o rtl/build/vv32_core_tb.vvp \
		rtl/vv32_pkg.sv rtl/vv32_core.sv rtl/tb/vv32_core_tb.sv
	$(VVP) rtl/build/vv32_core_tb.vvp

check: test examples rtl-test
	PYTHONPATH=src $(PYTHON) tools/check_isa_sync.py

clean:
	rm -rf build rtl/build src/*.egg-info src/victory_v/__pycache__ tests/__pycache__
