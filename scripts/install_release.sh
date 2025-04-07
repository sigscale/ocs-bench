#!/bin/bash
# Install an Erlang/OTP release package

APP_NAME=ocs_bench

cd ${HOME}
if [ -f "releases/RELEASES" ];
then
	OLD_VER=$(erl -noinput -eval '{ok, [R]} = file:consult("releases/RELEASES"), {release, _, Vsn, _, _, permanent} = lists:keyfind(permanent, 6, R), io:fwrite("~s", [Vsn]), init:stop()' | sed -e 's/'$APP_NAME'-//')
fi
APP_NEW=$(basename -as .tar.gz releases/${APP_NAME}-*.tar.gz | sort --version-sort | tail -1)
if [ -z "$APP_NEW" ];
then
	echo "Release package not found."
	exit 1
fi
tar -zxf releases/$APP_NEW.tar.gz
INSTDIR="$HOME/lib"
APPDIRS=$(sed -e 's|.*{\([a-z][a-zA-Z_0-9]*\),[[:blank:]]*\"\([0-9.]*\)\".*|{\1,\"\2\",\"'$INSTDIR'\"},|' -e '1s|^.*$|[|' -e '$s|\,$|]|' releases/$APP_NEW.rel | tr -d "\r\n")
SASLVER=$(erl -noinput -eval 'application:load(sasl), {ok, Vsn} = application:get_key(sasl, vsn), io:fwrite("~s", [Vsn]), init:stop()')

# Compare old and new release versions
if [ -n "$OLD_VER" ] && [ "$APP_NEW" != "$APP_NAME-$OLD_VER" ] && [ -d "lib/$APP_NAME-$OLD_VER" ];
then
	# Perform an OTP release upgrade
	OTP_NODE="${APP_NAME}@$(echo $HOSTNAME | sed -e 's/\..*//')"
	cp releases/$APP_NEW/sys.config releases/$APP_NEW/sys.config.dist
	if [ -f "releases/$APP_NAME-$OLD_VER/sys.config.dist" ];
	then
		echo "Merging previous system configuration localizations (sys.config) ..."
		diff --text --unified releases/$APP_NAME-$OLD_VER/sys.config.dist \
				releases/$APP_NAME-$OLD_VER/sys.config \
				> releases/$APP_NAME-$OLD_VER/sys.config.patch || :
		if patch releases/$APP_NEW/sys.config releases/$APP_NAME-$OLD_VER/sys.config.patch;
		then
			echo "... merge done."
		else
			echo "... merge failed."
			echo "Using previous system configuration without any newly distributed changes."
			sed -e "s/$APP_NAME-$OLD_VER/$APP_NEW/" \
					releases/$APP_NAME-$OLD_VER/sys.config > releases/$APP_NEW/sys.config
		fi
	else
		echo "Using previous system configuration localizations (sys.config) without any newly distributed changes."
		sed -e "s/$APP_NAME-$OLD_VER/$APP_NEW/" \
				releases/$APP_NAME-$OLD_VER/sys.config > releases/$APP_NEW/sys.config
	fi
	if epmd -names 2> /dev/null | grep -q "^name $APP_NAME at";
	then
		# Upgrade using rpc
		RPC_SNAME=$(id -un)
		echo "Performing an in-service upgrade ..."
		if echo -e "4.2\n$SASLVER"  | sort --check=quiet --version-sort;
		then
			if erl -noshell -sname $RPC_SNAME \
					-eval "rpc:call('$OTP_NODE', application, stop, [sasl])" \
					-eval "rpc:call('$OTP_NODE', application, set_env, [sasl, releases_dir, \"$HOME/releases\"])" \
					-eval "rpc:call('$OTP_NODE', application, start, [sasl])" \
					-eval "rpc:call('$OTP_NODE', systools, make_relup, [\"releases/$APP_NEW\", [\"releases/$APP_NAME-$OLD_VER\"], [\"releases/$APP_NAME-$OLD_VER\"], [{path,[\"lib/*/ebin\"]}, {outdir, \"releases/$APP_NEW\"}]])" \
					-eval "{ok, _} = rpc:call('$OTP_NODE', release_handler, set_unpacked, [\"$HOME/releases/$APP_NEW.rel\", $APPDIRS])" \
					-eval "{ok, _, _} = rpc:call('$OTP_NODE', release_handler, install_release, [\"$APP_NEW\", [{update_paths, true}]])" \
					-eval "ok = rpc:call('$OTP_NODE', release_handler, make_permanent, [\"$APP_NEW\"])" \
					-s init stop;
			then
				echo "... done."
			else
				echo "... failed."
				exit 1
			fi
		else
			if erl -noshell -sname $RPC_SNAME \
					-eval "rpc:call('$OTP_NODE', application, start, [sasl])" \
					-eval "rpc:call('$OTP_NODE', systools, make_relup, [\"releases/$APP_NEW\", [\"releases/$APP_NAME-$OLD_VER\"], [\"releases/$APP_NAME-$OLD_VER\"], [{path,[\"lib/*/ebin\"]}, {outdir, \"releases/$APP_NEW\"}]])" \
					-eval "{ok, _} = rpc:call('$OTP_NODE', release_handler, set_unpacked, [\"releases/$APP_NEW.rel\", $APPDIRS])" \
					-eval "{ok, _, _} = rpc:call('$OTP_NODE', release_handler, install_release, [\"$APP_NEW\", [{update_paths, true}]])" \
					-eval "ok = rpc:call('$OTP_NODE', release_handler, make_permanent, [\"$APP_NEW\"])" \
					-s init stop;
			then
				echo "... done."
			else
				echo "... failed."
				exit 1
			fi
		fi
	else
		# Start sasl, perform upgrade, stop started applications
		echo "Performing an out-of-service upgrade ..."
		if echo -e "4.2\n$SASLVER"  | sort --check=quiet --version-sort;
		then
			if ERL_LIBS=lib RELDIR=$HOME/releases erl -noshell \
					-sname $OTP_NODE -config releases/$APP_NAME-$OLD_VER/sys \
					-eval "application:start(sasl)" \
					-eval "application:load($APP_NAME)" \
					-eval "systools:make_relup(\"releases/$APP_NEW\", [\"releases/$APP_NAME-$OLD_VER\"], [\"releases/$APP_NAME-$OLD_VER\"], [{path,[\"lib/*/ebin\"]}, {outdir, \"releases/$APP_NEW\"}])" \
					-eval "{ok, _} = release_handler:set_unpacked(\"$HOME/releases/$APP_NEW.rel\", $APPDIRS)" \
					-eval "{ok, _, _} = release_handler:install_release(\"$APP_NEW\", [{update_paths, true}])" \
					-eval "ok = release_handler:make_permanent(\"$APP_NEW\")" \
					-s init stop;
			then
				echo "... done."
			else
				echo "... failed."
				exit 1
			fi
		else
			if ERL_LIBS=lib RELDIR=releases erl -noshell -sname $OTP_NODE -config releases/$APP_NAME-$OLD_VER/sys \
					-eval "application:start(sasl)" \
					-eval "application:load($APP_NAME)" \
					-eval "systools:make_relup(\"releases/$APP_NEW\", [\"releases/$APP_NAME-$OLD_VER\"], [\"releases/$APP_NAME-$OLD_VER\"], [{path,[\"lib/*/ebin\"]}, {outdir, \"releases/$APP_NEW\"}])" \
					-eval "{ok, _} = release_handler:set_unpacked(\"releases/$APP_NEW.rel\", $APPDIRS)" \
					-eval "{ok, _, _} = release_handler:install_release(\"$APP_NEW\", [{update_paths, true}])" \
					-eval "ok = release_handler:make_permanent(\"$APP_NEW\")" \
					-s init stop;
			then
				echo "... done."
			else
				echo "... failed."
				exit 1
			fi
		fi
	fi
else
	# Install release via shell
	echo "Installing an initial release ..."
	if echo -e "4.2\n$SASLVER"  | sort --check=quiet --version-sort;
	then
		if RELDIR=$HOME/releases erl -noshell -eval "application:start(sasl)" \
				-eval "ok = release_handler:create_RELEASES(\"$HOME/releases\", \"$HOME/releases/$APP_NEW.rel\", $APPDIRS)" \
				-s init stop;
		then
			echo "... done."
		else
			echo "... failed."
			exit 1
		fi
	else
		if RELDIR=releases erl -noshell -eval "application:start(sasl)" \
				-eval "ok = release_handler:create_RELEASES(code:root_dir(), \"$HOME/releases\", \"$HOME/releases/$APP_NEW.rel\", $APPDIRS)" \
				-s init stop;
		then
			echo "... done."
		else
			echo "... failed."
			exit 1
		fi
	fi
	if ! test -f releases/RELEASES;
	then
		exit 1
	fi
	cp releases/$APP_NEW/sys.config releases/$APP_NEW/sys.config.dist
fi
ERTS=$(grep "^\[{release," releases/RELEASES | sed -e 's/^\[{release,[[:blank:]]*\"//' -e 's/^[^"]*\",[[:blank:]]*\"//' -e 's/^[^"]*\",[[:blank:]]*\"//' -e 's/^\([0-9.]*\).*/\1/')
echo "$ERTS $APP_NEW" > releases/start_erl.data

