# Makefile for the Arrow language project (Linux)
#
#   make            build everything: ./arrow-interp (Phase 1) and ./arrowc (Phase 2)
#   make interp     build only the interpreter (needs only flex, bison, gcc)
#   make compiler   build only the LLVM compiler
#   make test       run the test-suite
#   make clean      remove generated files
#
# If llvm-config is not found automatically:  make LLVM_CONFIG=/path/to/llvm-config

CC          ?= gcc
FLEX        ?= flex
BISON       ?= bison
# llvm-config is looked up under its usual names; override with  make LLVM_CONFIG=...
LLVM_CONFIG ?= $(firstword $(foreach c,llvm-config llvm-config-20 llvm-config-19 llvm-config-18 llvm-config-17 llvm-config-16,$(shell command -v $(c) 2>/dev/null)))
CFLAGS      ?= -O2 -g
WARN        := -Wall -Wextra -Wno-unused-function -Wno-unused-parameter

COMMON      := src/common/ast.c src/common/sema.c
INC         := -Isrc/common

.PHONY: all interp compiler test clean check-llvm
all: interp compiler
interp: arrow-interp
compiler: arrowc build/arrow_rt.o

# ---------------------------------------------------------------- Phase 1
build/p1/parser.tab.c build/p1/parser.tab.h: src/phase1/interp.y
	@mkdir -p build/p1
	$(BISON) -d -Wall -o build/p1/parser.tab.c $<

build/p1/lex.yy.c: src/lexer.l build/p1/parser.tab.h
	$(FLEX) -o $@ $<

arrow-interp: build/p1/parser.tab.c build/p1/lex.yy.c $(COMMON) src/common/ast.h src/common/sema.h
	$(CC) $(CFLAGS) $(WARN) $(INC) -Ibuild/p1 -o $@ build/p1/parser.tab.c build/p1/lex.yy.c $(COMMON) -pthread

# ---------------------------------------------------------------- Phase 2
check-llvm:
	@test -n "$(LLVM_CONFIG)" || { echo "error: llvm-config not found. Install the LLVM development package (see README.pdf) or run: make LLVM_CONFIG=/path/to/llvm-config"; exit 1; }
build/p2/parser.tab.c build/p2/parser.tab.h: src/phase2/compiler.y
	@mkdir -p build/p2
	$(BISON) -d -Wall -o build/p2/parser.tab.c $<

build/p2/lex.yy.c: src/lexer.l build/p2/parser.tab.h
	$(FLEX) -o $@ $<

build/arrow_rt.o: src/runtime/arrow_rt.c
	@mkdir -p build
	$(CC) $(CFLAGS) -Wall -c -o $@ $<

arrowc: check-llvm build/p2/parser.tab.c build/p2/lex.yy.c $(COMMON) src/phase2/bce.c src/phase2/bce.h build/arrow_rt.o
	$(CC) $(CFLAGS) $(WARN) $(INC) -Ibuild/p2 -Isrc/phase2 \
	    -DARROW_RT_OBJ='"$(abspath build/arrow_rt.o)"' \
	    $(shell $(LLVM_CONFIG) --cflags) \
	    -o $@ build/p2/parser.tab.c build/p2/lex.yy.c $(COMMON) src/phase2/bce.c \
	    $(shell $(LLVM_CONFIG) --ldflags --libs --system-libs)

# ---------------------------------------------------------------- tests
test: all
	bash tests/run_tests.sh

clean:
	rm -rf build arrow-interp arrowc tests/tmp
