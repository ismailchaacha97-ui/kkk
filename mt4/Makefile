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

.PHONY: test cross clean extract

$(CORE): $(MQ4)
	@awk '/CORE BEGIN/{flag=1;next} /CORE END/{flag=0} flag' $(MQ4) > $(CORE)
	@echo "extracted $$(wc -l < $(CORE)) lines of core from $(MQ4)"

extract: $(CORE)

$(BIN): $(CORE) test_ladder.cpp
	$(CXX) -std=c++17 -Wall -Wextra -Wno-unused-parameter -O1 -o $(BIN) test_ladder.cpp

test: $(BIN)
	@./$(BIN)

# Independent cross-check: the Python simulator's ladder table and this C++ core
# must agree on cumulative lot and basket take profit, since both claim to model
# the same system.
cross: test
	@python3 ../noloss/noloss_sim.py > /dev/null 2>&1 || true
	@python3 crosscheck.py

clean:
	@rm -f $(CORE) $(BIN)
