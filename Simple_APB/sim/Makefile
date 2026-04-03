.PHONY: all help comp elab run run_gui env dirs wave_tcl clean

all: help

# ---- User Configuration (override via command line) ----
TOP           ?= top_apb_tb
TIMESCALE     ?= 1ns/1ps
SEED          ?= random
RTL_FLIST     ?= ../include/rtl_filelist.f
DV_FLIST      ?= ../include/dv_filelist.f
EXTRA_FLIST   ?=
INC_DIRS      ?=
DEFINES       ?=
EXTRA_OPTS    ?=
WAVE          ?= YES
WAVE_DEPTH    ?= all

# ---- Output Directories ----
DB_DIR        := db
LOG_DIR       := log
WAVE_DIR      := wave
SCR_DIR       := scripts

# ---- Tool ----
XRUN          := xrun

# ---- Internal Flags ----
FLIST_FLAGS   := -f $(RTL_FLIST) -f $(DV_FLIST)
ifneq ($(strip $(EXTRA_FLIST)),)
  FLIST_FLAGS += $(addprefix -f ,$(EXTRA_FLIST))
endif

INC_FLAGS     := $(addprefix -incdir ,$(INC_DIRS))
DEF_FLAGS     := $(addprefix +define+,$(DEFINES))
WAVE_TCL      := $(SCR_DIR)/probe.tcl

ifeq ($(WAVE),YES)
  BATCH_WAVE  := -input $(WAVE_TCL)
else
  BATCH_WAVE  :=
endif

# ---- xrun Options ----
COMMON_OPTS   := $(FLIST_FLAGS)                    \
                 -top $(TOP)                       \
                 -timescale $(TIMESCALE)            \
                 -xmlibdirname $(DB_DIR)/xcelium.d \
                 $(INC_FLAGS)                      \
                 $(DEF_FLAGS)                      \
                 -64bit -sv -messages              \
                 -nospecify                         \
                 $(EXTRA_OPTS)

COMP_OPTS     := $(COMMON_OPTS)                    \
                 -compile                          \
                 -l $(LOG_DIR)/compile.log

ELAB_OPTS     := $(COMMON_OPTS)                    \
                 -elaborate                        \
                 -access +rwc                      \
                 -l $(LOG_DIR)/elab.log

SIM_OPTS      := -R                                \
                 -xmlibdirname $(DB_DIR)/xcelium.d \
                 -64bit -messages                  \
                 -access +rwc                      \
                 -seed $(SEED)                     \
                 -l $(LOG_DIR)/sim.log             \
                 $(EXTRA_OPTS)

GUI_OPTS      := -gui -input $(WAVE_TCL)

# ---- Targets ----

env:
	@command -v $(XRUN) >/dev/null 2>&1 || \
	  { echo ""; \
	    echo "  ERROR: $(XRUN) not found in PATH."; \
	    echo "  Please run:  source setup.csh"; \
	    echo ""; \
	    exit 1; }

dirs:
	@mkdir -p $(DB_DIR) $(LOG_DIR) $(WAVE_DIR) $(SCR_DIR)

wave_tcl: dirs
	@echo "database -open waves -into $(WAVE_DIR)/waves.shm -default" >  $(WAVE_TCL)
	@echo "probe -create $(TOP) -depth $(WAVE_DEPTH) -all -shm"      >> $(WAVE_TCL)

comp: env dirs
	$(XRUN) $(COMP_OPTS)

elab: env dirs
	$(XRUN) $(ELAB_OPTS)

run: elab wave_tcl
	$(XRUN) $(SIM_OPTS) $(BATCH_WAVE)

run_gui: elab wave_tcl
	$(XRUN) $(SIM_OPTS) $(GUI_OPTS)

clean:
	rm -rf $(DB_DIR) $(LOG_DIR) $(WAVE_DIR) $(SCR_DIR)
	rm -rf .simvision .xrun.history *.key *.err *.dsn *.trn

help:
help:
	@echo ""
	@echo "══════════════════════════════════════════════════════════════════"
	@echo "         Cadence Xcelium (xrun) - Module-Level Simulation"
	@echo "══════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "  Environment Setup (run once per terminal session):"
	@echo "    source setup.csh"
	@echo "  Or manually:"
	@echo "    module load xlm && module load adsim && module load vscode"
	@echo ""
	@echo "══════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "  Targets         Description"
	@echo "  ──────────────  ──────────────────────────────────────────────"
	@echo "  make comp       Compile only (syntax check)"
	@echo "  make elab       Compile + Elaborate"
	@echo "  make run        Compile + Elaborate + Simulate (batch)"
	@echo "  make run_gui    Compile + Elaborate + Simulate (GUI)"
	@echo "  make clean      Remove all generated directories"
	@echo "  make help       Show this message"
	@echo ""
	@echo "  Dependency: run / run_gui -> elab (includes compile)"
	@echo ""
	@echo "══════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "  Configurable Variables                            [current]"
	@echo "  ──────────────────────────────────────────────────────────────"
	@printf "    %-14s%-26s%s\n" "TOP" "Top-level module" "$(TOP)"
	@printf "    %-14s%-26s%s\n" "RTL_FLIST" "RTL filelist" "$(RTL_FLIST)"
	@printf "    %-14s%-26s%s\n" "DV_FLIST" "DV / TB filelist" "$(DV_FLIST)"
	@printf "    %-14s%-26s%s\n" "EXTRA_FLIST" "Additional filelists" "$(EXTRA_FLIST)"
	@printf "    %-14s%-26s%s\n" "TIMESCALE" "Timescale" "$(TIMESCALE)"
	@printf "    %-14s%-26s%s\n" "SEED" "Random seed" "$(SEED)"
	@printf "    %-14s%-26s%s\n" "WAVE" "Dump waveform (batch)" "$(WAVE)"
	@printf "    %-14s%-26s%s\n" "WAVE_DEPTH" "Probe depth" "$(WAVE_DEPTH)"
	@printf "    %-14s%-26s%s\n" "INC_DIRS" "Include directories" "$(INC_DIRS)"
	@printf "    %-14s%-26s%s\n" "DEFINES" "Macro definitions" "$(DEFINES)"
	@printf "    %-14s%-26s%s\n" "EXTRA_OPTS" "Extra xrun options" "$(EXTRA_OPTS)"
	@echo ""
	@echo "══════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "  Examples:"
	@echo "    make run"
	@echo "    make run      TOP=tb_adder SEED=12345"
	@echo "    make run_gui  DEFINES=\"DEBUG FAST_SIM\""
	@echo "    make run      EXTRA_FLIST=\"ip/uart.f ip/spi.f\""
	@echo "    make comp     EXTRA_OPTS=\"-nowarn NONPRT\""
	@echo "    make run      WAVE=NO"
	@echo ""
	@echo "══════════════════════════════════════════════════════════════════"
	@echo ""