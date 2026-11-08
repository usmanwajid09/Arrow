# Makefile for the Arrow language project (Linux)
#
#   make            build interpreter: ./arrow-interp (Phase 1)
#   make interp     build only the interpreter (needs only flex, bison, gcc)
#   make test       run the test-suite
#   make clean      remove generated files

CC          ?= gcc
FLEX        ?= flex
BISON       ?= bison
CFLAGS      ?= -O2 -g
WARN        := -Wall -Wextra -Wno-unused-function -Wno-unused-parameter

COMMON      := src/common/ast.c src/common/sema.c
INC         := -Isrc/common

.PHONY: all interp test clean
all: interp
interp: arrow-interp

# ---------------------------------------------------------------- Phase 1
build/p1/parser.tab.c build/p1/parser.tab.h: src/phase1/interp.y
	@mkdir -p build/p1
	$(BISON) -d -Wall -o build/p1/parser.tab.c $<

build/p1/lex.yy.c: src/lexer.l build/p1/parser.tab.h
	$(FLEX) -o $@ $<

arrow-interp: build/p1/parser.tab.c build/p1/lex.yy.c $(COMMON) src/common/ast.h src/common/sema.h
	$(CC) $(CFLAGS) $(WARN) $(INC) -Ibuild/p1 -o $@ build/p1/parser.tab.c build/p1/lex.yy.c $(COMMON) -pthread

# ---------------------------------------------------------------- tests
test: interp
	bash tests/run_tests.sh

clean:
	rm -rf build arrow-interp tests/tmp
