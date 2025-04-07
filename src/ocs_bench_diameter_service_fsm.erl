%%% ocs_bench_diameter_service_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2020-2025 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc This {@link //stdlib/gen_statem. gen_statem} behaviour callback
%%% 	module implements a DIAMETER service handler in the
%%% 	{@link //ocs_bench. ocs_bench} application.
%%%
-module(ocs_bench_diameter_service_fsm).
-copyright('Copyright (c) 2020-2025 SigScale Global Inc.').

-behaviour(gen_statem).

%% export the ocs_bench_diameter_service_fsm API
-export([]).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([wait_for_start/3, wait_for_peer/3, connected/3]).

-include_lib("kernel/include/inet.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("kernel/include/logger.hrl").

-type state() :: wait_for_start | wait_for_peer | connected.

-record(statedata,
		{transport :: undefined | reference(),
		address :: inet:ip_address(),
		service :: term(),
		options :: list()}).
-type statedata() :: #statedata{}.

-define(BASE_APPLICATION, ocs_diameter_base_application).
-define(BASE_APPLICATION_DICT, diameter_gen_base_rfc6733).
-define(BASE_APPLICATION_CALLBACK, ocs_diameter_base_application_cb).
-define(RO_APPLICATION_ID, 4).
-define(RO_APPLICATION, ocs_diameter_3gpp_ro_application).
-define(RO_APPLICATION_DICT, diameter_gen_3gpp_ro_application).
-define(RO_APPLICATION_CALLBACK, ocs_bench_diameter_ro_cb).
-define(IANA_PEN_3GPP, 10415).
-define(IANA_PEN_SigScale, 50386).

%%----------------------------------------------------------------------
%%  The ocs_bench_diameter_service_fsm API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The ocs_bench_diameter_service_fsm gen_statem callbacks
%%----------------------------------------------------------------------

-spec callback_mode() -> Result
	when
		Result :: gen_statem:callback_mode_result().
%% @doc Set the callback mode of the callback module.
%% @see //stdlib/gen_statem:callback_mode/0
%% @private
%%
callback_mode() ->
	[state_functions, state_enter].

-spec init(Args) -> Result
	when
		Args :: [term()],
		Result :: {ok, State, Data} | {ok, State, Data, Actions}
				| ignore | {stop, Reason},
		State :: state(),
		Data :: statedata(),
		Actions :: Action | [Action],
		Action :: gen_statem:action(),
		Reason :: term().
%% @doc Initialize the {@module} finite state machine.
%% @see //stdlib/gen_statem:init/1
%% @private
%%
init([Address] = _Args) ->
	Options = [],
	ServiceOptions = service_options(Options),
	Service = default,
	diameter:subscribe(Service),
	case diameter:start_service(Service, ServiceOptions) of
		ok ->
			process_flag(trap_exit, true),
			Data = #statedata{address = Address,
					service = Service, options = Options},
			{ok, wait_for_start, Data};
		{error, Reason} ->
			{stop, Reason}
	end.

-spec wait_for_start(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>wait_for_start</em> state.
%% @private
%%
wait_for_start(enter = _EventType, _EventContent, _Data) ->
	keep_state_and_data;
wait_for_start(info, #diameter_event{info = start},
		#statedata{address = Address,
		service = Service} = Data) ->
	Options = transport_options(diameter_tcp, Address),
	case diameter:add_transport(Service, Options) of
		{ok, Transport} ->
			NewData = Data#statedata{transport = Transport},
			{next_state, wait_for_peer, NewData};
		{error, Reason} ->
			{stop, Reason, Data}
	end;
wait_for_start(info,
		{'ETS-TRANSFER', service, _, []}, _Data) ->
	keep_state_and_data.

-spec wait_for_peer(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>wait_for_peer</em> state.
%% @private
%%
wait_for_peer(enter = _EventType, _EventContent, _Data) ->
	keep_state_and_data;
wait_for_peer(info, {'ETS-TRANSFER', subscriber, _, []}, _Data) ->
	keep_state_and_data;
wait_for_peer(info, #diameter_event{info = Event, service = Service},
		#statedata{service = Service, transport = Ref} = Data)
		when element(1, Event) == up, element(2, Event) == Ref ->
	{_PeerRef, #diameter_caps{origin_host = {_, Peer}}} = element(3, Event),
	?LOG_NOTICE("DIAMETER peer connected~nservice: ~w~npeer: ~p~n",
			[Service, binary_to_list(Peer)]),
	{next_state, connected, Data};
wait_for_peer(info, #diameter_event{info = {watchdog, Ref, _PeerRef,
		{_From, _To}, _Config}},
		#statedata{transport = Ref} = Data) ->
	{next_state, wait_for_peer, Data};
wait_for_peer(info, #diameter_event{info = Event, service = Service},
		#statedata{service = Service} = Data) ->
	?LOG_NOTICE("DIAMETER event~nservice: ~w~nevent: ~p~n", [Service, Event]),
	{next_state, wait_for_peer, Data};
wait_for_peer(info, {'EXIT', _Pid, noconnection}, Data) ->
	{stop, noconnection, Data};
wait_for_peer(info, #diameter_event{info = stop, service = Service},
		#statedata{service = Service} = Data) ->
	{stop, stop, Data}.

-spec connected(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>connected</em> state.
%% @private
%%
connected(enter = _EventType, wait_for_peer = _EventContent, _Data) ->
	case supervisor:start_child(ocs_bench_diameter_ro_fsm_sup, [[], []]) of
		{ok, _Fsm} ->
			keep_state_and_data;
		{error, Reason} ->
			{error, Reason}
	end;
connected(info, #diameter_event{info = {down, Ref, Peer, _Config},
		service = Service}, #statedata{transport = Ref} = Data) ->
	{_PeerRef, #diameter_caps{origin_host = {_, Peer1}}} = Peer,
	?LOG_NOTICE("DIAMETER peer disconnected~nservice: ~w~npeer: ~p~n",
			[Service, binary_to_list(Peer1)]),
	{stop, down, Data};
connected(info, #diameter_event{info = {watchdog, Ref, _PeerRef,
		{_From, _To}, _Config}},
		#statedata{transport = Ref} = Data) ->
	{next_state, connected, Data};
connected(info, #diameter_event{info = Event, service = Service},
		#statedata{service = Service} = Data) ->
	?LOG_NOTICE("DIAMETER event~nservice: ~w~nevent: ~p~n", [Service, Event]),
	{next_state, connected, Data};
connected(info, {'EXIT', _Pid, noconnection}, Data) ->
	{stop, noconnection, Data};
connected(info, #diameter_event{info = stop, service = Service},
		#statedata{service = Service} = Data) ->
	{stop, stop, Data}.

-spec handle_event(EventType, EventContent, State, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		State :: state(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(State).
%% @doc Handles events received in any state.
%% @private
%%
handle_event(_EventType, _EventContent, State, Data) ->
	{next_state, State, Data}.

-spec terminate(Reason, State, Data) -> any()
	when
		Reason :: normal | shutdown | {shutdown, term()} | term(),
		State :: state(),
		Data ::  statedata().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_statem:terminate/3
%% @private
%%
terminate(stop, _State, _Data) ->
	ok;
terminate(_Reason, _State,
		#statedata{transport = Transport, service = Service} = _Data) ->
	case diameter:remove_transport(Service, Transport) of
		ok ->
			diameter:stop_service(Service);
		{error, Reason} ->
			?LOG_ERROR("Failed to remove transport~n"
					"service: ~w~ntransport: ~p~nerror: ~w~n",
					[Service, Transport, Reason])
	end.

-spec code_change(OldVsn, OldState, OldData, Extra) -> Result
	when
		OldVsn :: Version | {down, Version},
		Version ::  term(),
		OldState :: state(),
		OldData :: statedata(),
		Extra :: term(),
		Result :: {ok, NewState, NewData} |  Reason,
		NewState :: state(),
		NewData :: statedata(),
		Reason :: term().
%% @doc Update internal state data during a release upgrade&#047;downgrade.
%% @see //stdlib/gen_statem:code_change/3
%% @private
%%
code_change(_OldVsn, OldState, OldData, _Extra) ->
	{ok, OldState, OldData}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec transport_options(Transport, Address) -> Options
	when
		Transport :: diameter_tcp | diameter_sctp,
		Address :: inet:ip_address(),
		Options :: tuple().
%% @doc Returns options for a DIAMETER transport layer.
%% @hidden
transport_options(Transport, Address) ->
	{ok, RemoteAddress} = application:get_env(remote_address),
	{ok, RemotePort} = application:get_env(remote_port),
	Opts = [{transport_module, Transport},
			{transport_config, [{reuseaddr, true}, {ip, Address},
			{raddr, RemoteAddress}, {rport, RemotePort}]}],
	{connect, Opts}.

-spec service_options(Options) -> Options
	when
		Options :: list().
%% @doc Returns options for a DIAMETER service.
%% @hidden
service_options(Options) ->
	{ok, Vsn} = application:get_key(vsn),
	Version = list_to_integer([C || C <- Vsn, C /= $.]),
	{ok, Hostname} = inet:gethostname(),
	Options1 = case lists:keymember('Origin-Host', 1, Options) of
		true ->
			Options;
		false when length(Hostname) > 0 ->
			[{'Origin-Host', Hostname} | Options];
		false ->
			[{'Origin-Host', "ocs-bench"} | Options]
	end,
	Options2 = case lists:keymember('Origin-Realm', 1, Options1) of
		true ->
			Options1;
		false ->
			OriginRealm = case inet_db:res_option(domain) of
				S when length(S) > 0 ->
					S;
				_ ->
					"example.net"
			end,
			[{'Origin-Realm', OriginRealm} | Options1]
	end,
	Options2 ++ [{'Vendor-Id', ?IANA_PEN_SigScale},
		{'Product-Name', "SigScale OCS Benchmark"},
		{'Firmware-Revision', Version},
		{'Supported-Vendor-Id', [?IANA_PEN_3GPP]},
		{'Auth-Application-Id', [?RO_APPLICATION_ID]},
		{restrict_connections, false},
		{string_decode, false},
		{application, [{alias, ?BASE_APPLICATION},
				{dictionary, ?BASE_APPLICATION_DICT},
				{module, ?BASE_APPLICATION_CALLBACK},
				{request_errors, callback}]},
		{application, [{alias, ?RO_APPLICATION},
				{dictionary, ?RO_APPLICATION_DICT},
				{module, ?RO_APPLICATION_CALLBACK},
				{request_errors, callback}]}].

