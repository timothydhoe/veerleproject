.PHONY: py-install py-lint py-test r-install

py-install:
	cd python && uv sync --extra dev

py-lint:
	cd python && uv run ruff check src tests
	cd python && uv run mypy src

py-test:
	cd python && uv run pytest tests/

r-install:
	cd r && Rscript install.R
