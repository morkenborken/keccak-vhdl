SIM ?= ghdl
TOPLEVEL_LANG ?= vhdl
SRC_DIR = ../src
VHDL_SOURCES =  $(SRC_DIR)/keccak_pkg.vhd
VHDL_SOURCES += $(SRC_DIR)/keccak_sponge.vhd
VHDL_SOURCES += $(SRC_DIR)/keccak_pad.vhd
VHDL_SOURCES += $(SRC_DIR)/keccak_axi4s.vhd
TOPLEVEL = keccak_axi4s
MODULE = test_keccak_axi4s
SIM_ARGS = --wave=$(TOPLEVEL).ghw
export PYTHONPATH=../src

include $(shell cocotb-config --makefiles)/Makefile.sim

gui: sim
	@gtkwave $(TOPLEVEL).ghw

#clean:
#	-@rm $(TOPLEVEL).ghw
