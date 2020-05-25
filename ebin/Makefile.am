## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

appdir = $(beamdir)
app_DATA = ocs_bench.app
EXTRA_DIST = ocs_bench.app

beam_DATA = ocs_bench_app.beam \
		ocs_bench_sup.beam \
		ocs_bench_diameter_service_fsm_sup.beam \
		ocs_bench_diameter_ro_fsm_sup.beam \
		ocs_bench_server.beam \
		ocs_bench_diameter_service_fsm.beam \
		ocs_bench_diameter_ro_fsm.beam \
		ocs_bench_diameter_ro_cb.beam

%.beam:$(top_srcdir)/src/%.erl
	$(ERLC) $(ERLCFLAGS) $<

%.app:   %.app-in
	sed -e 's/%APP_NAME%/$(PACKAGE_NAME)/' \
			-e 's/%APP_VERSION%/$(PACKAGE_VERSION)/' \
			-e 's#%APP_PRIV%#$(ERLANG_INSTALL_LIB_DIR)/$(PACKAGE_NAME)-$(PACKAGE_VERSION)/priv#' < $< > $@

CLEANFILES = $(beam_DATA) $(app_DATA)

