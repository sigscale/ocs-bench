## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

modhtml = ocs_bench_app.html \
		ocs_bench_sup.html \
		ocs_bench_rest_fsm_sup.html \
		ocs_bench_diameter_service_fsm_sup.html \
		ocs_bench_diameter_ro_fsm_sup.html \
		ocs_bench_server.html \
		ocs_bench_rest_fsm.html \
		ocs_bench_diameter_service_fsm.html \
		ocs_bench_diameter_ro_fsm.html \
		ocs_bench_diameter_ro_cb.html

doc_DATA = overview.edoc $(modhtml) \
		modules-frame.html overview-summary.html \
		index.html stylesheet.css \
		sigscale-logo.png \
		supervision.png \
		testing.svg

overview.edoc: overview.edoc-in
	sed -e 's!%VERSION%!$(VERSION)!' \
			-e 's!%DESCRIPTION%!$(PACKAGE)!' < $< > $@

%.html:$(top_srcdir)/src/%.erl	overview.edoc $(top_srcdir)/doc/supervision.edoc
	$(ERL) -noshell -run edoc_run application \
			"'$(PACKAGE_NAME)'" "'$(top_builddir)'" \
			'[{sort_functions,false},{private,true},{todo,true},{source_path,["$(top_srcdir)/src"]},{subpackages,false},{def,{docsrc,"$(top_srcdir)/doc/{@?}"}},{stylesheet_file, "$(top_srcdir)/doc/sigscale.css"}]'
	for i in `ls *.html`; do \
			sed -e 's!erlang logo!sigscale logo!' \
					-e 's!href=\"http://www.erlang.org/\"!href=\"http://www.sigscale.org/\"!' \
					-e 's!erlang.png!sigscale-logo.png!' $$i > $$i.tmp; \
			mv $$i.tmp $$i; \
	done
	-cp -n $(top_srcdir)/doc/sigscale-logo.png .
	-cp -n $(top_srcdir)/doc/supervision.png .
	-cp -n $(top_srcdir)/doc/testing.svg .

CLEANFILES = overview.edoc edoc-info index.html \
		modules-frame.html overview-summary.html packages-frame.html \
		stylesheet.css erlang.png $(modhtml)

