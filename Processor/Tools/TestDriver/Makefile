PYTHON ?= python3

# Test the test infrastructure itself: runner result checks and simulation limits.
.PHONY: test
test:
	$(PYTHON) -B -m unittest discover -s Tests -p 'Test*.py' -v
