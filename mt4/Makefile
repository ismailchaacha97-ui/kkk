# Extracts the CORE section of RuleOP_Ladder.mq4 and compiles it as C++17,
# so the ladder arithmetic that MetaEditor will compile is the exact arithmetic
# the tests run. Nothing here is a re-implementation.
#
#   make test    extract + build + run the unit tests
#   make cross   also cross-check the core against the Python simulator
#   make clean

MQ4     := RuleOP_Ladder.mq4
CORE    := core_under_test.inc
BIN     := test_ladder

.PHONY: test cross clean extract api ea

$(CORE): $(MQ4)
	@awk '/CORE BEGIN/{flag=1;next} /CORE END/{flag=0} flag' $(MQ4) > $(CORE)
	@echo "extracted $$(wc -l < $(CORE)) lines of core from $(MQ4)"

extract: $(CORE)

$(BIN): $(CORE) test_ladder.cpp
	$(CXX) -std=c++17 -Wall -Wextra -Wno-unused-parameter -O1 -o $(BIN) test_ladder.cpp

test: $(BIN) api ea
	@./$(BIN)

# Independent cross-check: the Python simulator's ladder table and this C++ core
# must agree on cumulative lot and basket take profit, since both claim to model
# the same system.
cross: test
	@python3 ../noloss/noloss_sim.py > /dev/null 2>&1 || true
	@python3 crosscheck.py

clean:
	@rm -f $(CORE) $(BIN) ind_under_test.inc test_api \
	       $(EA_CORE) $(EA_BIN)

# The MT4 half of the indicator, compiled against an MQL4 API stub. This proves
# the drawing/order-reading code is syntactically valid and behaves, which the
# core-only test cannot reach. It is NOT a substitute for MetaEditor.
ind_under_test.inc: $(MQ4)
	@grep -v '^#property' $(MQ4) \
	  | sed -E 's/const (datetime|double|long|int) &([a-z_]+)\[\]/const \1_vec \&\2/g' \
	  > ind_under_test.inc
	@echo "generated ind_under_test.inc (#property stripped, OnCalculate " \
	      "signature aliased)"

test_api: ind_under_test.inc test_api.cpp mql4_api_stub.cpp mql4_api_stub.h
	$(CXX) -std=c++17 -Wall -Wextra -Wno-unused-parameter -Wno-unused-variable \
	       -DNOLOSS_HAS_INPUTS -O1 -o test_api test_api.cpp mql4_api_stub.cpp

api: test_api
	@./test_api

# The EA's decision logic and circuit breakers, extracted and compiled the same
# way. The breakers are the only thing in a Rule OP system that protects the
# account, and a reversed comparison operator means the stop never fires.
EA      := RuleOP_LadderEA.mq4
EA_CORE := ea_core_under_test.inc
EA_BIN  := test_ea_core

$(EA_CORE): $(EA)
	@awk '/EA CORE BEGIN/{flag=1;next} /EA CORE END/{flag=0} flag' $(EA) > $(EA_CORE)
	@echo "extracted $$(wc -l < $(EA_CORE)) lines of EA core from $(EA)"

$(EA_BIN): $(EA_CORE) test_ea_core.cpp
	$(CXX) -std=c++17 -Wall -Wextra -O1 -o $(EA_BIN) test_ea_core.cpp

ea: $(EA_BIN)
	@./$(EA_BIN)
