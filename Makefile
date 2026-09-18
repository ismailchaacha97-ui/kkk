# VWAP Pro - build and test
#
# The whole library is header only and is compiled by MetaTrader itself.
# These targets compile the *same headers* with a normal C++ compiler so
# that every formula on the chart is covered by an assertion.
#
#   make test     build and run every test suite        (the main target)
#   make dump     build the bar dumper used by the python tools
#   make js       third implementation: JS port vs the compiled engine
#   make check    static MQL4 rules + two independent cross checks
#   make bench    per-bar cost at several history lengths
#   make fixture  regenerate the synthetic M1 fixture
#   make all      test + check
#   make clean

CXX      ?= g++
CXXFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter -std=c++11
DEFS     := -DVWAPPRO_CPP_TEST
INC      := -IMQL4/Include/VWAPPro -Itests

BUILD    := build
TESTS    := test_time test_math test_volume test_engine test_data
BINS     := $(addprefix $(BUILD)/,$(TESTS))

FIXTURE  := tests/fixtures/synth_m1_eurusd.csv

.PHONY: all test dump js check bench fixture clean dirs

all: test check

dirs:
	@mkdir -p $(BUILD)

$(BUILD)/%: tests/%.cpp $(wildcard MQL4/Include/VWAPPro/*.mqh) $(wildcard tests/*.h) | dirs
	$(CXX) $(CXXFLAGS) $(DEFS) $(INC) $< -o $@

$(BUILD)/dump_bars: tests/dump_bars.cpp $(wildcard MQL4/Include/VWAPPro/*.mqh) | dirs
	$(CXX) $(CXXFLAGS) $(DEFS) $(INC) $< -o $@

test: $(BINS)
	@fail=0; \
	for t in $(BINS); do \
	  echo ""; ./$$t || fail=1; \
	done; \
	echo ""; \
	if [ $$fail -eq 0 ]; then echo "ALL SUITES PASSED"; else echo "SOME SUITES FAILED"; exit 1; fi

dump: $(BUILD)/dump_bars

check: dump js
	python3 tools/check_mql4.py
	@if [ -f $(FIXTURE) ]; then \
	  python3 tools/crosscheck.py $(FIXTURE); \
	else \
	  echo "no fixture - run 'make fixture' first"; \
	fi

js: dump
	node tools/check_js_port.js $(FIXTURE)

bench: dump
	python3 tools/benchmark.py

fixture:
	python3 tools/make_fixture.py --days 15 --out $(FIXTURE)

clean:
	rm -rf $(BUILD)
