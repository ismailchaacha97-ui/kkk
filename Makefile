PY := .venv/bin/python
DATA ?= data/XAUUSD_H1.csv
SYMBOL ?= XAUUSD

.PHONY: help setup test demo compare sweep clean

help:
	@echo "make setup                     create .venv and install deps"
	@echo "make test                      run the test suite"
	@echo "make demo                      run all methods on synthetic data"
	@echo "make compare DATA=path.csv     backtest all methods on your data"
	@echo "make sweep DATA=path.csv S=magic_candle"
	@echo "make clean                     remove caches and run output"

setup:
	python3 -m venv .venv
	$(PY) -m pip install -q --upgrade pip
	$(PY) -m pip install -q -r requirements.txt

test:
	$(PY) -m pytest tests/ -q

demo:
	$(PY) -m kkk.cli demo

compare:
	$(PY) -m kkk.cli compare $(DATA) --symbol $(SYMBOL) --out runs/$(SYMBOL)

sweep:
	$(PY) -m kkk.cli sweep $(DATA) --symbol $(SYMBOL) -s $(or $(S),magic_candle)

clean:
	find . -name __pycache__ -type d -prune -exec rm -rf {} +
	rm -rf .pytest_cache runs .mypy_cache
