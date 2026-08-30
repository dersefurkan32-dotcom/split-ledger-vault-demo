.PHONY: test fmt build ci

test:
	forge test -vv

fmt:
	forge fmt

build:
	forge build --skip test

ci: fmt
	forge fmt --check
	forge build --skip test
	forge test -vv
