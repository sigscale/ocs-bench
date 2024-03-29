## configure.ac
## vim: ts=3
##
## Process this file with autoconf to produce a configure script.
##
## Boilerplate:  standard boilerplate code
##
AC_INIT([ocs_bench], [1.2.5], [issues@sigscale.org])
AC_COPYRIGHT([Copyright (c) 2020-2021 SigScale Global Inc.])
AC_PREREQ(2.63)
AC_CONFIG_SRCDIR([src/ocs_bench_app.erl])
AC_CONFIG_HEADERS([config.h])
AC_LANG([Erlang])
AM_INIT_AUTOMAKE([-Wno-portability])

##
## Options:  control options to configure, support code for the options
##
AC_ARG_ENABLE([debug],
		[AS_HELP_STRING([--enable-debug], [enable debugging (default is no)])])
CFLAGS="${CFLAGS} -Wall"


##
## Programs:  check for programs needed by the configure process,
##            the build process, or by one of the programs being built
##
AC_ERLANG_NEED_ERL
AC_ERLANG_NEED_ERLC
if test -z "${ERLCFLAGS}" ; then
	ERLCFLAGS="-W -v"
fi
if test "x$enable_debug" == xyes ; then
	ERLCFLAGS="$ERLCFLAGS +debug_info"
fi
AC_ERLANG_SUBST_LIB_DIR
if test -z "${ERLANG_INSTALL_LIB_DIR}" ; then
	ERLANG_INSTALL_LIB_DIR=$ERLANG_LIB_DIR
fi
AC_ERLANG_SUBST_ROOT_DIR
AC_ERLANG_SUBST_ERTS_VER
AC_PROG_MKDIR_P
AC_PROG_INSTALL
AC_PROG_LN_S
AC_ERLANG_SUBST_INSTALL_LIB_DIR
appdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION
erldir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/src
beamdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/ebin
docdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/doc
reldir=$ERLANG_INSTALL_LIB_DIR/../releases
AC_SUBST(appdir)
AC_SUBST(erldir)
AC_SUBST(beamdir)
AC_SUBST(reldir)


##
## Libraries:  check for libraries
##
AC_ERLANG_CHECK_LIB([kernel], [], [AC_MSG_ERROR([kernel was not found!])])
AC_ERLANG_CHECK_LIB([stdlib], [], [AC_MSG_ERROR([stdlib was not found!])])
AC_ERLANG_CHECK_LIB([sasl], [], [AC_MSG_ERROR([sasl was not found!])])
AC_ERLANG_CHECK_LIB([mnesia], [], [AC_MSG_ERROR([mnesia was not found!])])
AC_ERLANG_CHECK_LIB([compiler], [], [AC_MSG_ERROR([compiler was not found!])])
AC_ERLANG_CHECK_LIB([crypto], [], [AC_MSG_ERROR([crypto was not found!])])
AC_ERLANG_CHECK_LIB([syntax_tools], [], [AC_MSG_ERROR([syntax_tools was not found!])])
AC_ERLANG_CHECK_LIB([inets], [], [AC_MSG_ERROR([inets was not found!])])
AC_ERLANG_CHECK_LIB([asn1], [], [AC_MSG_ERROR([asn1 was not found!])])
AC_ERLANG_CHECK_LIB([public_key], [], [AC_MSG_ERROR([public_key was not found!])])
AC_ERLANG_CHECK_LIB([xmerl], [], [AC_MSG_ERROR([xmerl was not found!])])
AC_ERLANG_CHECK_LIB([ssl], [], [AC_MSG_ERROR([ssl was not found!])])
AC_ERLANG_CHECK_LIB([diameter], [], [AC_MSG_ERROR([diameter was not found!])])
AC_ERLANG_CHECK_LIB([radius], [], [AC_MSG_ERROR([radius was not found!])])
AC_ERLANG_CHECK_LIB([mochiweb], [], [AC_MSG_ERROR([mochiweb was not found!])])
AC_ERLANG_CHECK_LIB([zj], [], [AC_MSG_ERROR([zj was not found!])])
AC_ERLANG_CHECK_LIB([ocs], [], [AC_MSG_ERROR([ocs was not found!])])


##
## Headers:  check for header files
##

##
## Typedefs & Structures:  check for typedefs, structures,
##                         and compiler characteristics.
##


##
## Functions:  check for library functions
##


##
## Output:  create output files
##

AC_OUTPUT([Makefile ebin/Makefile doc/Makefile
		$PACKAGE_NAME.rel sys.config])

