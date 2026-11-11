.PHONY: lint test

lint:
	nix develop -c ruff check DuxAiUsage/collectors tests
	nix develop -c ruff format --check DuxAiUsage/collectors tests

test:
	nix develop -c python -m pytest tests/ -q
