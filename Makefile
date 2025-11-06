##########################
# ---- Introduction ---- #
##########################

# Welcome to the EECS 470 standard makefile!

# NOTE: you should only need to modify the "Executable Compilation" section
# namely the TESTBENCH, SOURCES, and SYNTH_FILES variables
# look for the 'P1 TODO' or 'P1 NOTE' markers below

# reference table of all make targets:

# make           <- runs the default target, set explicitly below as 'make sim'
.DEFAULT_GOAL = sim
# ^ this overrides using the first listed target as the default

# make sim         <- execute the simulation testbench (simv)
# make build/simv  <- compiles simv from the testbench and SOURCES

# make syn             <- execute the synthesized module testbench (syn.simv)
# make build/syn.simv  <- compiles syn.simv from the testbench and *.vg SYNTH_FILES
# make synth/*.vg      <- synthesize the top level module in SOURCES for use in syn.simv
# make slack           <- a phony command to print the slack of any synthesized modules

# make verdi     <- runs the Verdi GUI debugger for simulation
# make syn.verdi <- runs the Verdi GUI debugger for synthesis

# make clean     <- remove files created during compilations (but not synthesis)
# make nuke      <- remove all files created during compilation and synthesis
# make clean_run_files <- remove per-run output files
# make clean_exe       <- remove compiled executable files
# make clean_synth     <- remove generated synthesis files

######################################################
# ---- Compilation Commands and Other Variables ---- #
######################################################

# this is a global clock period variable used in the tcl script and referenced in testbenches
export CLOCK_PERIOD = 10.0

# the Verilog Compiler command and arguments
VCS = vcs -sverilog -xprop=tmerge +vc -Mupdate -Mdir=build/csrc -line -full64 -kdb -lca -nc \
      -debug_access+all+reverse $(VCS_BAD_WARNINGS) +define+CLOCK_PERIOD=$(CLOCK_PERIOD)
# a SYNTH define is added when compiling for synthesis that can be used in testbenches

# remove certain warnings that generate MB of text but can be safely ignored
VCS_BAD_WARNINGS = +warn=noTFIPC +warn=noDEBUG_DEP +warn=noENUMASSIGN +warn=noLCA_FEATURES_ENABLED

# a reference library of standard structural cells that we link against when synthesizing
LIB = /usr/caen/misc/class/eecs470/lib/verilog/lec25dscc25.v

# the EECS 470 synthesis script
TCL_SCRIPT = 470synth.tcl

# Set the shell's pipefail option: causes return values through pipes to match the last non-zero value
# (useful for, i.e. piping to `tee`)
SHELL := $(SHELL) -o pipefail

####################################
# ---- Executable Compilation ---- #
####################################

# You should only need to modify this section, and only the following variables:


# P1 TODO: change TESTBENCH and SOURCES to match your current modules
# options for SOURCES:   ps4-assign.sv, ps4-if_else.sv | ps8.sv
# options for TESTBENCH: ps4_test.sv                   | ps8_test.sv
TESTBENCH   = blake3_test.sv
SOURCES     = blake3.sv
SYNTH_FILES = synth/blake3.vg

# the .vg rule is automatically generated below when the name of the file matches its top level module
# P1 NOTE: this doesn't work for ps4-assign.sv and ps4-if_else.sv, but you don't need synthesis for P1

# the normal simulation executable will run your testbench on the original modules
build/simv: $(TESTBENCH) $(SOURCES) | build
	@$(call PRINT_COLOR, 5, compiling the simulation executable $@)
	$(VCS) $(TESTBENCH) $(SOURCES) -o $@
	@$(call PRINT_COLOR, 6, finished compiling $@)
# NOTE: we reference variables with $(VARIABLE), and can make use of the automatic variables: ^, @, <, etc
# see: https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html for explanations

# a make pattern rule to generate the .vg synthesis files
# pattern rules use the % as a wildcard to match multiple possible targets
synth/%.vg: $(SOURCES) $(TCL_SCRIPT) | synth
	@$(call PRINT_COLOR, 5, synthesizing the $* module)
	@$(call PRINT_COLOR, 3, this might take a while...)
	cd synth && \
	MODULE=$* SOURCES="$(SOURCES)" \
	dc_shell-t -f ../$(TCL_SCRIPT) | tee $*-synth.out
	@$(call PRINT_COLOR, 6, finished synthesizing $@)
# this also generates many other files, see the tcl script's introduction for info on each of them

# the synthesis executable runs your testbench on the synthesized versions of your modules
build/syn.simv: $(TESTBENCH) $(SYNTH_FILES) | build
	@$(call PRINT_COLOR, 5, compiling the synthesis executable $@)
	$(VCS) +define+SYNTH $(TESTBENCH) $(SYNTH_FILES) $(LIB) -o $@
	@$(call PRINT_COLOR, 6, finished compiling $@)
# we need to link the synthesized modules against LIB, so this differs slightly from simv above
# but we still compile with the same non-synthesizable testbench

# a phony target to view the slack in the *.rep synthesis report file
slack:
	grep --color=auto "slack" synth/*.rep
.PHONY: slack

#####################################
# ---- Running the Executables ---- #
#####################################

# these targets run the compiled executable and save the output to a .out file
# their respective files are "build/program.out" or "build/program.syn.out"

sim: build/simv
	@$(call PRINT_COLOR, 5, running $<)
	cd build && ./simv | tee program.out
	@$(call PRINT_COLOR, 2, output saved to build/program.out)

syn: build/syn.simv
	@$(call PRINT_COLOR, 5, running $<)
	cd build && ./syn.simv | tee program.syn.out
	@$(call PRINT_COLOR, 2, output saved to build/program.syn.out)

# NOTE: phony targets don't create files matching their name, and make will always run their commands
# make doesn't know how files get created, so we tell it about these explicitly:
.PHONY: sim syn

###################
# ---- Verdi ---- #
###################

# verdi is the synopsys debug system, and an essential tool in EECS 470

# Options to launch Verdi when running the executable
RUN_VERDI_OPTS = -gui=verdi -verdi_opts "-ultra" -no_save
# Not sure why no_save is needed right now. Otherwise prints an error
VERDI_DIR = /tmp/$(USER)470
VERDI_TEMPLATE = /usr/caen/misc/class/eecs470/verdi-config/initialnovas.rc

# verdi hates us: we must use the /tmp folder for all verdi files or it will crash
# this adds much unecessary complexity in the makefile
# A directory for verdi, specified in the build/novas.rc file.
$(VERDI_DIR) $(VERDI_DIR)/verdiLog:
	mkdir -p $@
# Symbolic link from the build folder to VERDI_DIR in /tmp
build/verdiLog: $(VERDI_DIR)/verdiLog build
	ln -s $(VERDI_DIR)/verdiLog build
# make a custom novas.rc for your username matching VERDI_DIR
build/novas.rc: $(VERDI_TEMPLATE) | build
	sed s/UNIQNAME/$${USER}/ $< > $@

# now the actual targets to launch verdi
verdi: build/simv build/novas.rc build/verdiLog $(VERDI_DIR)
	cd build && ./simv $(RUN_VERDI_OPTS)

syn.verdi: build/syn.simv build/novas.rc build/verdiLog $(VERDI_DIR)
	cd build && ./syn.simv $(RUN_VERDI_OPTS)

.PHONY: verdi syn.verdi

###############################
# ---- Build Directories ---- #
###############################

# Directories for holding build files or run outputs
# Targets that need these directories should add them after a pipe.
# ex: "target: dep1 dep2 ... | build"
build synth:
	mkdir -p $@
# Don't leave any files in these, they will be deleted by clean commands

#####################
# ---- Cleanup ---- #
#####################

# You should only clean your directory if you think something has built incorrectly
# or you want to prepare a clean directory for e.g. git (first check your .gitignore).
# Please avoid cleaning before every build. The point of a makefile is to
# automatically determine which targets have dependencies that are modified,
# and to re-build only those as needed; avoiding re-building everything everytime.

# 'make clean' removes build/output files, 'make nuke' removes all generated files
# clean_* commands clean certain groups of files

clean: clean_exe clean_run_files
	@$(call PRINT_COLOR, 6, note: clean is split into multiple commands that you can call separately: clean_exe and clean_run_files)

# use cautiously, this can cause hours of recompiling in later projects
nuke: clean clean_synth
	@$(call PRINT_COLOR, 6, note: nuke is split into multiple commands that you can call separately: clean_synth)

clean_exe:
	@$(call PRINT_COLOR, 3, removing compiled executable files)
	rm -rf build
	rm -rf *simv *.daidir csrc *.key vcdplus.vpd vc_hdrs.h
	rm -rf verdi* novas* *fsdb*

clean_run_files:
	@$(call PRINT_COLOR, 3, removing per-run outputs)
	rm -rf *.out *.dump

clean_synth:
	@$(call PRINT_COLOR, 1, removing synthesis files)
	rm -rf synth
	rm -rf *.vg *_svsim.sv *.res *.rep *.ddc *.chk *.syn *-synth.out *.mr *.pvl command.log

.PHONY: clean nuke clean_%

######################
# ---- Printing ---- #
######################

# this is a GNU Make function with two arguments: PRINT_COLOR(color: number, msg: string)
# it does all the color printing throughout the makefile
PRINT_COLOR = if [ -t 0 ]; then tput setaf $(1) ; fi; echo $(2); if [ -t 0 ]; then tput sgr0; fi
# colors: 0:black, 1:red, 2:green, 3:yellow, 4:blue, 5:magenta, 6:cyan, 7:white
# other numbers are valid, but aren't specified in the tput man page

# Make functions are called like this:
# $(call PRINT_COLOR,3,Hello World!)
# NOTE: adding '@' to the start of a line avoids printing the command itself, only the output
