#
# Copyright (c) 2012, Joyent, Inc. All rights reserved.
#
# Makefile for IMGAPI
#

#
# Vars, Tools, Files, Flags
#
NAME		:= imgapi
DOC_FILES	 = index.restdown design.restdown
JS_FILES	:= $(shell ls *.js) \
	$(shell find lib test -name '*.js' | grep -v '/tmp/')
JSL_CONF_NODE	 = tools/jsl.node.conf
JSL_FILES_NODE	 = $(JS_FILES)
JSSTYLE_FILES	 = $(JS_FILES)
JSSTYLE_FLAGS	 = -f tools/jsstyle.conf
SMF_MANIFESTS_IN = smf/manifests/imgapi.xml.in
NODEUNIT	:= ./node_modules/.bin/nodeunit
CLEAN_FILES += ./node_modules

# The prebuilt sdcnode version we want. See
# "tools/mk/Makefile.node_prebuilt.targ" for details.
ifeq ($(shell uname -s),SunOS)
	NODE_PREBUILT_VERSION=v0.8.14
	NODE_PREBUILT_TAG=zone
endif


include ./tools/mk/Makefile.defs
ifeq ($(shell uname -s),SunOS)
	include ./tools/mk/Makefile.node_prebuilt.defs
else
	include ./tools/mk/Makefile.node.defs
endif
include ./tools/mk/Makefile.smf.defs

RELEASE_TARBALL	:= $(NAME)-pkg-$(STAMP).tar.bz2
TMPDIR          := /tmp/$(STAMP)



#
# Targets
#
.PHONY: all
all: $(SMF_MANIFESTS) images.joyent.com-node-hack updates.joyent.com-node-hack | $(NODEUNIT) $(REPO_DEPS)
	$(NPM) install

# Node hack for images.joyent.com and updates.joyent.com
#
# Fake out 'Makefile.node_prebuilt.*' by symlinking build/node
# to the node we want to use. We can't use sdcnode here because
# of GCC mismatch with current sdcnode builds.
.PHONY: images.joyent.com-node-hack
images.joyent.com-node-hack:
	if [[ -f "$(HOME)/THIS-IS-IMAGES.JOYENT.COM.txt" ]]; then \
		if [[ ! -d "$(TOP)/build/node" ]]; then \
			mkdir -p $(TOP)/build; \
			(cd $(TOP)/build && ln -s $(HOME)/opt/node-0.8.14 node); \
			touch $(NODE_EXEC); \
			touch $(NPM_EXEC); \
		fi; \
	fi
.PHONY: updates.joyent.com-node-hack
updates.joyent.com-node-hack:
	if [[ -f "$(HOME)/THIS-IS-UPDATES.JOYENT.COM.txt" ]]; then \
		if [[ ! -d "$(TOP)/build/node" ]]; then \
			mkdir -p $(TOP)/build; \
			(cd $(TOP)/build && ln -s /opt/local node); \
			touch $(NODE_EXEC); \
			touch $(NPM_EXEC); \
		fi; \
	fi

$(NODEUNIT): | $(NPM_EXEC)
	$(NPM) install

.PHONY: test test-kvm7 test-images.joyent.com
test: | $(NODEUNIT)
	./test/runtests -lp  # test local 'public' mode
	./test/runtests -l   # test local 'dc' mode
test-kvm7: | $(NODEUNIT)
	./tools/rsync-to-kvm7
	./tools/runtests-on-kvm7
test-images.joyent.com: | $(NODEUNIT)
	./test/runtests -p

.PHONY: release
release: all
	@echo "Building $(RELEASE_TARBALL)"
	mkdir -p $(TMPDIR)/root/opt/smartdc/$(NAME)
	mkdir -p $(TMPDIR)/site
	touch $(TMPDIR)/site/.do-not-delete-me
	mkdir -p $(TMPDIR)/root
	cp -r \
		$(TOP)/bin \
		$(TOP)/build \
		$(TOP)/main.js \
		$(TOP)/lib \
		$(TOP)/etc \
		$(TOP)/node_modules \
		$(TOP)/package.json \
		$(TOP)/smf \
		$(TOP)/test \
		$(TMPDIR)/root/opt/smartdc/$(NAME)
	mkdir -p $(TMPDIR)/root/var/svc
	cp -r \
		$(TOP)/sdc/setup \
		$(TOP)/sdc/configure \
		$(TMPDIR)/root/var/svc
	(cd $(TMPDIR) && $(TAR) -jcf $(TOP)/$(RELEASE_TARBALL) root site)
	@rm -rf $(TMPDIR)

.PHONY: publish
publish: release
	@if [[ -z "$(BITS_DIR)" ]]; then \
		@echo "error: 'BITS_DIR' must be set for 'publish' target"; \
		exit 1; \
	fi
	mkdir -p $(BITS_DIR)/$(NAME)
	cp $(TOP)/$(RELEASE_TARBALL) $(BITS_DIR)/$(NAME)/$(RELEASE_TARBALL)

.PHONY: deploy-images.joyent.com
deploy-images.joyent.com:
	@echo '# Deploy to images.joyent.com. This is a *production* server.'
	@echo '# Press <Enter> to continue, <Ctrl+C> to cancel.'
	@read
	ssh root@images.joyent.com ' \
		set -x \
		&& cd /root/services \
		&& cp -PR imgapi imgapi.`date "+%Y%m%dT%H%M%SZ"` \
		&& cd /root/services/imgapi \
		&& git fetch origin \
		&& git pull --rebase origin master \
		&& PATH=/opt/local/gnu/bin:$$PATH make clean all \
		&& svcadm restart imgapi \
		&& tail -f `svcs -L imgapi` | bunyan -o short'

.PHONY: deploy-updates.joyent.us
deploy-updates.joyent.us:
	@echo '# Deploy to updates.joyent.us. This is a *production* server.'
	@echo '# Press <Enter> to continue, <Ctrl+C> to cancel.'
	@read
	ssh root@updates.joyent.us ' \
		set -x \
		&& cd /root/services \
		&& cp -PR imgapi imgapi.`date "+%Y%m%dT%H%M%SZ"` \
		&& cd /root/services/imgapi \
		&& git fetch origin \
		&& git pull --rebase origin master \
		&& PATH=/opt/local/gnu/bin:$$PATH make clean all \
		&& svcadm restart imgapi \
		&& tail -f `svcs -L imgapi` | bunyan -o short'

.PHONY: devrun
devrun:
	node-dev main.js -f tools/imgapi.config.local-signature-auth.json | bunyan -o short

.PHONY: dumpvar
dumpvar:
	@if [[ -z "$(VAR)" ]]; then \
		echo "error: set 'VAR' to dump a var"; \
		exit 1; \
	fi
	@echo "$(VAR) is '$($(VAR))'"

include ./tools/mk/Makefile.deps
ifeq ($(shell uname -s),SunOS)
	include ./tools/mk/Makefile.node_prebuilt.targ
else
	include ./tools/mk/Makefile.node.targ
endif
include ./tools/mk/Makefile.smf.targ
include ./tools/mk/Makefile.targ
