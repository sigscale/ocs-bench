%%% ocs_bench_rest_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2020 SigScale Global Inc.
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
%%% 	module implements a transaction handler for HTTP REST API calls in the
%%% 	{@link //ocs_bench. ocs_bench} application.
%%%
-module(ocs_bench_rest_fsm).
-copyright('Copyright (c) 2020 SigScale Global Inc.').

-behaviour(gen_statem).

%% export the ocs_bench_rest_fsm API
-export([]).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([client_request/3, client_response/3, wait_request/3, wait_response/3]).

-include_lib("kernel/include/logger.hrl").
-include_lib("kernel/include/inet.hrl").

-type state() :: client_request | client_response
		| wait_request | wait_response.

-record(statedata,
		{active :: pos_integer(),
		mean :: pos_integer(),
		deviation :: 0..100,
		start :: pos_integer(),
		uri :: string(),
		auth :: {Athorization :: string(), BasicAuth :: string()},
		hostname :: undefined | string(),
		address :: undefined | inet:ip_address(),
		request :: reference()}).
-type statedata() :: #statedata{}.

%%----------------------------------------------------------------------
%%  The ocs_bench_rest_fsm API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The ocs_bench_rest_fsm gen_statem callbacks
%%----------------------------------------------------------------------

-spec callback_mode() -> Result
	when
		Result :: gen_statem:callback_mode_result().
%% @doc Set the callback mode of the callback module.
%% @see //stdlib/gen_statem:callback_mode/0
%% @private
%%
callback_mode() ->
	state_functions.

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
init(_Args) ->
	{ok, Active} = application:get_env(active),
	{ok, Mean} = application:get_env(mean),
	{ok, Deviation} = application:get_env(deviation),
	{ok, Uri} = application:get_env(rest_uri),
	{ok, User} = application:get_env(rest_user),
	{ok, Password} = application:get_env(rest_pass),
	UserPass = User ++ ":" ++ Password,
	BasicAuth = base64:encode_to_string(UserPass),
	Authorization = {"authorization", "Basic " ++ BasicAuth},
	service = ets:new(service, [public, named_table]),
	Data = #statedata{active = Active, mean = Mean,
			deviation = Deviation, uri = Uri,
			auth = Authorization},
	{ok, client_request, Data, rand:uniform(4000)}.

-spec client_request(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>wait_request</em> state.
%% @private
%%
client_request(timeout = _EventType, _EventContent,
		#statedata{address = undefined, hostname = undefined,
		uri = Uri, auth = Authorization} = Data) ->
	Start = erlang:system_time(millisecond),
	?LOG_INFO("Begin phase 0: add REST client"),
	{ok, Hostname} = inet:gethostname(),
	case inet:gethostbyname(Hostname, inet) of
		{ok, #hostent{h_addrtype = inet, h_addr_list = [Address | _]}} ->
			Path = "/ocs/v1/client/" ++ inet:ntoa(Address),
			Accept = {"accept", "application/json"},
			Request = {Uri ++ Path, [Authorization, Accept]},
			case httpc:request(get, Request, [], [{sync, false}], tmf) of
				{ok, RequestId} when is_reference(RequestId) ->
					NewData = Data#statedata{request = RequestId,
							start = Start, address = Address,
							hostname = Hostname},
					{next_state, client_response, NewData};
				{error, Reason} ->
					{stop, Reason, Data}
			end;
		{error, Reason} ->
			{stop, Reason, Data}
	end;
client_request(timeout = _EventType, _EventContent,
		#statedata{address = Address, hostname = Hostname,
		uri = Uri, auth = Authorization} = Data)
		when is_tuple(Address), is_list(Hostname) ->
	Start = erlang:system_time(millisecond),
	Id = inet:ntoa(Address),
	Path = Uri ++ "/ocs/v1/client",
	ContentType = "application/json",
	Accept = {"accept", ContentType},
	RequestHeaders = [Authorization, Accept],
	RequestBody = zj:encode(#{"id" => Id, "protocol" => "DIAMETER"}),
	Request = {Path, RequestHeaders, ContentType, RequestBody},
	case httpc:request(post, Request, [], [{sync, false}], tmf) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#statedata{request = RequestId, start = Start},
			{next_state, client_response, NewData};
		{error, Reason} ->
			{stop, Reason, Data}
	end;
client_request(_EventType, _EventContent, _Data) ->
keep_state_and_data.

-spec client_response(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>client_response</em> state.
%% @private
%%
client_response(info = _EventType,
		{http, {RequestId, {{_, 404, _}, _Headers, _Body}}} = _EventContent,
		#statedata{request = RequestId, start = Start} = Data) ->
		NewData = Data#statedata{request = undefined},
	{next_state, client_request, NewData, timeout(Start, Data)};
client_response(info = _EventType,
		{http, {RequestId, {{_, StatusCode, _}, _Headers, Body}}},
		#statedata{request = RequestId, start = Start} = Data)
		when StatusCode == 200; StatusCode == 201 ->
	case zj:decode(Body) of
		{ok, #{"id" := Id}} ->
			case inet:parse_address(Id) of
				{ok, Address} ->
					?LOG_INFO("End phase 0: add REST client"),
					?LOG_INFO("Begin phase 1: add service identifiers"),
					NewData = Data#statedata{address = Address},
					{next_state, wait_request, NewData, timeout(Start, NewData)};
				{error, Reason} ->
					{stop, Reason, Data}
			end;
		{Error, _Partial, _Remaining} when Error == error; Error == incomplete ->
			{stop, Error, Data}
	end;
client_response(info = _EventType,
		{http, {RequestId, {{_, StatusCode, _}, _Headers, _Body}}},
		#statedata{request = RequestId} = Data) ->
	{stop, StatusCode, Data};
client_response(info = _EventType, {http, {RequestId, {error, Reason}}},
		#statedata{request = RequestId} = Data) ->
	{stop, Reason, Data}.

-spec wait_request(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>wait_request</em> state.
%% @private
%%
wait_request(timeout = _EventType, _EventContent,
		#statedata{active = Active, uri = Uri, auth = Authorization} = Data) ->
	Start = erlang:system_time(millisecond),
	case ets:info(service, size) of
		N when N < Active ->
			Path = Uri ++ "/serviceInventoryManagement/v2/service/",
			ContentType = "application/json",
			Accept = {"accept", ContentType},
			RequestHeaders = [Authorization, Accept],
			Chars = [#{"name" => "serviceIdentity", "value" => imsi()},
					#{"name" => "serviceAkaK",
						"value" => binary_to_hex(crypto:strong_rand_bytes(16))},
					#{"name" => "serviceAkaOPc",
						"value" => binary_to_hex(crypto:strong_rand_bytes(16))}],
			ServiceSpecification = #{"id" => "1",
					"href" => "/catalogManagement/v2/serviceSpecification/1"},
			RequestBody = zj:encode(#{"serviceCharacteristic" => Chars,
					"serviceSpecification" => ServiceSpecification}),
			Request = {Path, RequestHeaders, ContentType, RequestBody},
			case httpc:request(post, Request, [], [{sync, false}], tmf) of
				{ok, RequestId} when is_reference(RequestId) ->
					NewData = Data#statedata{request = RequestId, start = Start},
					{next_state, wait_response, NewData};
				{error, Reason} ->
					{stop, Reason, Data}
			end;
		N ->
			?LOG_INFO("End phase 1: added ~b service identifiers", [N]),
			keep_state_and_data
	end.

-spec wait_response(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>wait_response</em> state.
%% @private
%%
wait_response(info = _EventType,
		{http, {RequestId, {{_, 201, _}, _Headers, Body}}} = _EventContent,
		#statedata{request = RequestId, start = Start} = Data) ->
		NewData = Data#statedata{request = undefined},
	case zj:decode(Body) of
		{ok, #{"serviceCharacteristic" := Chars}} ->
			F = fun(#{"name" := "serviceIdentity", "value" := Id}, {_, K, OPc}) ->
						{Id, K, OPc};
					(#{"name" := "serviceAkak", "value" := K}, {Id, _, OPc}) ->
						{Id, K, OPc};
					(#{"name" := "serviceOPc", "value" := OPc}, {Id, K, _}) ->
						{Id, K, OPc};
					(_, Acc) ->
						Acc
			end,
			case lists:foldl(F, {undefined, undefined, undefined}, Chars) of
				{Id, K, OPc} when is_list(Id) ->
					ets:insert(service, {Id, K, OPc}),
					{next_state, wait_request, NewData, timeout(Start, Data)};
				_ ->
					{stop, bad_service, NewData}
			end;
		{Error, _Partial, _Remaining} when Error == error; Error == incomplete ->
			{stop, Error, NewData}
	end;
wait_response(info = _EventType,
		{http, {RequestId, {{_, StatusCode, _}, _Headers, _Body}}},
		#statedata{request = RequestId} = Data) ->
	{stop, StatusCode, Data};
wait_response(info = _EventType, {http, {RequestId, {error, Reason}}},
		#statedata{request = RequestId} = Data) ->
	{stop, Reason, Data}.

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
handle_event(_EventType, _EventContent, _State, _Data) ->
	keep_state_and_data.

-spec terminate(Reason, State, Data) -> any()
	when
		Reason :: normal | shutdown | {shutdown, term()} | term(),
		State :: state(),
		Data ::  statedata().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_statem:terminate/3
%% @private
%%
terminate(_Reason, _State, _Data) ->
	ok.

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

-spec timeout(Start, StateData) -> Timeout
	when
		Start :: pos_integer(),
		StateData :: #statedata{},
		Timeout :: pos_integer().
%% @doc Returns a timeout taking into account the time it took to
%% 	process the current transaction, the configured `mean' rate
%% 	and random `deviation' percentage.
%% @hidden
timeout(Start, #statedata{mean = Mean, deviation = Deviation}) ->
	End = erlang:system_time(millisecond),
	case (1000 div Mean) - (End - Start) of
		Interval when Interval > 0 ->
			case (Interval * Deviation) div 100 of
				Range when Range > 0 ->
					Interval + (rand:uniform(Range * 2) - Range);
				_Range ->
					0
			end;
		_Interval ->
			0
	end.

-spec imsi() -> [$0..$9].
%% @doc Generate an IMSI.
%% @private
imsi() ->
	Charset = lists:seq($0, $9),
	imsi(Charset, []).
%% @hidden
imsi(Charset, Acc) when length(Acc) < 9 ->
	N = lists:nth(rand:uniform(10), Charset),
	imsi(Charset, [N | Acc]);
imsi(_, Acc) ->
	"001001" ++ Acc.

%% @hidden
binary_to_hex(B) when is_binary(B) ->
	binary_to_hex(B, []).
%% @hidden
binary_to_hex(<<N:4, Rest/bits>>, Acc) when N >= 10 ->
	binary_to_hex(Rest, [N - 10 + $a | Acc]);
binary_to_hex(<<N:4, Rest/bits>>, Acc) ->
	binary_to_hex(Rest, [N + $0 | Acc]);
binary_to_hex(<<>>, Acc) ->
	lists:reverse(Acc).

