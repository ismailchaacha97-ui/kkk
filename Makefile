PYTHON ?= python3

.PHONY: help install test lint format run demo real clean

help:
	@echo "make install  - install runtime dependencies"
	@echo "make test     - run the unit/integration test suite"
	@echo "make lint     - ruff check + format check"
	@echo "make format   - apply ruff formatting"
	@echo "make demo     - run both strategies on 60 synthetic sessions"
	@echo "make real     - fetch LEAN sample data and backtest it"
	@echo "make clean    - remove generated data and reports"

install:
	$(PYTHON) -m pip install -r requirements.txt

test:
	$(PYTHON) -m unittest discover -s tests -v

lint:
	ruff check daytrader tests scripts
	ruff format --check daytrader tests scripts

format:
	ruff format daytrader tests scripts
	ruff check --fix daytrader tests scripts

demo:
	$(PYTHON) -m daytrader compare --days 60 --out reports

real:
	$(PYTHON) scripts/fetch_lean_sample.py --out data_real
	$(PYTHON) -m daytrader compare --symbols SPY IBM BAC AIG \
		--data-dir data_real --no-generate --out reports/real

clean:
	rm -rf data reports data_real
	find . -name "__pycache__" -type d -prune -exec rm -rf {} +
