TAG=kennyballou
all: build
.PHONY: all

build: container blog

container:
	@docker build -t ${TAG} .

blog:
	@$(MAKE) -C blag
