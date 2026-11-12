ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
VOLUTA := $(ROOT)/bin/voluta

.PHONY: help init dry-run install update deps doctor apply browser karere theme docs-serve

help:
	@printf '%s\n' \
		'make init        Create personal settings' \
		'make dry-run     Preview install' \
		'make install     Install Voluta' \
		'make update      Deploy the current checkout' \
		'make deps        Install or repair dependencies' \
		'make doctor      Check the installation' \
		'make apply       Activate enabled integrations' \
		'make browser     Enable Brave/Prismwing/Gallery publishing' \
		'make karere      Install karere-custom-css for WhatsApp Web palette injection' \
		'make theme       Refresh Wallust consumers' \
		'make docs-serve  Preview docs at http://localhost:3000'

init:
	$(VOLUTA) init

dry-run:
	$(VOLUTA) install --dry-run

install:
	$(VOLUTA) install

update:
	$(VOLUTA) update

deps:
	$(VOLUTA) deps

doctor:
	$(VOLUTA) doctor

apply:
	$(VOLUTA) apply

browser:
	$(VOLUTA) feature enable browser
	@$(MAKE) --no-print-directory theme
	@printf '%s\n' \
		'Published. In Brave: set theme to GTK, disable Ultra/Darker theme,' \
		'then Load unpacked:' \
		'  Prismwing  ~/Code/projects/prismwing/extension' \
		'  Gallery    ~/.local/share/voluta/gallery'

karere:
	$(VOLUTA) feature enable karere
	$(VOLUTA) deps
	@$(MAKE) --no-print-directory theme
	@printf '%s\n' \
		'karere-custom-css replaces stock karere and loads ~/.config/karere/custom.css.' \
		'Reopen Karere if it was already running.'

theme:
	@$(ROOT)/tools/refresh-theme.sh

docs-serve:
	@command -v mdbook >/dev/null || { \
		echo 'mdBook is not installed. Install from https://github.com/rust-lang/mdBook/releases or with cargo install mdbook' >&2; \
		exit 1; \
	}
	@echo 'Documentation server at http://localhost:3000'
	mdbook serve $(ROOT)/docs
