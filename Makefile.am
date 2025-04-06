## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

SUBDIRS = ebin doc

if HAVE_SYSTEMD
systemdsystemunit_DATA = scripts/ocs_bench.service
env_DATA = scripts/ocs_bench
endif

script_SCRIPTS = scripts/install_release.sh

RELEASE_NAME = $(PACKAGE_NAME)-$(RELEASE_NAME)

.PHONY: release
release: $(RELEASE_NAME).tar.gz

$(RELEASE_NAME).rel:	$(PACKAGE_NAME).rel
	cp $(PACKAGE_NAME).rel $(RELEASE_NAME).rel

$(RELEASE_NAME).tar.gz: $(RELEASE_NAME).rel sys.config
	$(ERL) -noinput \
		-eval "systools:make_script(\"$(RELEASE_NAME)\")" \
		-eval "systools:make_tar(\"$(RELEASE_NAME)\", [{dirs, [include]}])" \
		-s init stop

install-data-hook: $(RELEASE_NAME).tar.gz
	$(MKDIR_P) $(DESTDIR)/$(reldir)
	$(INSTALL_DATA) $< $(DESTDIR)/$(reldir)

EXTRA_DIST = $(RELEASE_NAME).tar.gz

CLEANFILES = $(RELEASE_NAME).script $(RELEASE_NAME).boot $(RELEASE_NAME).tar.gz

install-data-hook: $(RELEASE_NAME).tar.gz
	$(MKDIR_P) $(DESTDIR)/$(reldir)
	$(INSTALL_DATA) $< $(DESTDIR)/$(reldir)
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/log

