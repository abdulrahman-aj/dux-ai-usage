.PHONY: lint test shots

lint:
	nix develop -c ruff check DuxAiUsage/collectors tests
	nix develop -c ruff format --check DuxAiUsage/collectors tests

test:
	nix develop -c python -m pytest tests/ -q

# Live screenshots of every surface at every density on THIS desktop.
shots:
	scripts/capture-shots.sh $(or $(OUT),shots)
