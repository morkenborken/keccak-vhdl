SIM ?= ghdl
TOPLEVEL_LANG ?= vhdl

include $(shell cocotb-config --makefiles)/Makefile.sim
VPI_PATH = $(shell cocotb-config --lib-name-path vpi ghdl)

SRC_DIR = ../src
VHDL_SOURCES =  $(SRC_DIR)/keccak_pkg.vhd
VHDL_SOURCES += $(SRC_DIR)/keccak_sponge.vhd
VHDL_SOURCES += $(SRC_DIR)/keccak_pad.vhd
VHDL_SOURCES += $(SRC_DIR)/keccak_axi4s.vhd

SIM_ARGS = --wave=$(TOPLEVEL).ghw

export PYTHONPATH=../src
TARGETS =

# Sponge
TARGETS += keccak_sponge
keccak_sponge: TOPLEVEL = keccak_sponge
keccak_sponge: MODULE = test_keccak_sponge

# Pad
TARGETS += keccak_pad
keccak_pad: TOPLEVEL = keccak_pad
keccak_pad: MODULE = test_keccak_pad

# Toplevel
TESTCASE =
TOPLEVEL =  keccak_axi4s
MODULE =  test_keccak_axi4s

$(COCOTB_RESULTS_FILE): $(TARGETS)

$(TARGETS):
	$(SIM) -m --workdir=sim_build -Psim_build --work=work $@
	MODULE=$(MODULE) TESTCASE= TOPLEVEL=$(TOPLEVEL) TOPLEVEL_LANG=$(TOPLEVEL_LANG) $(SIM) -r --workdir=$(SIM_BUILD) -P$(SIM_BUILD) --work=work $@ --vpi=$(VPI_PATH) --wave=$@.ghw

clean::
	rm -f $(COCOTB_RESULTS_FILE)
	rm *.ghw
