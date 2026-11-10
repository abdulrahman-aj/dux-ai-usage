.PHONY: lint test

lint:
	ruff check DuxAiUsage/collectors tests
	ruff format --check DuxAiUsage/collectors tests

test:
	python -m pytest tests/ -q
