.PHONY: lint test

lint:
	ruff check collectors tests
	ruff format --check collectors tests

test:
	python -m pytest tests/ -q
