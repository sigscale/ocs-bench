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
-export([client_request/3, client_response/3,
		service_request/3, service_response/3,
		product_request/3, product_response/3,
		balance_request/3, balance_response/3]).

-include_lib("kernel/include/logger.hrl").

-type state() :: client_request | client_response
		| service_request | service_response
		| product_request | service_response
		| balance_request | balance_response.

-record(statedata,
		{active :: pos_integer(),
		mean :: pos_integer(),
		deviation :: 0..100,
		id_type :: imsi | msisdn,
      id_prefix :: string(),
		id_n :: pos_integer(),
		start :: pos_integer(),
		uri :: string(),
		auth :: {Athorization :: string(), BasicAuth :: string()},
		address :: undefined | inet:ip_address(),
		request :: reference(),
		cursor :: term() | '$end_of_table',
		count = 0 :: non_neg_integer()}).
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
init([Address]) ->
	{ok, Active} = application:get_env(active),
	{ok, Mean} = application:get_env(mean),
	{ok, Deviation} = application:get_env(deviation),
	{ok, {IdType, Prefix, N}} = application:get_env(sub_id),
	{ok, Uri} = application:get_env(rest_uri),
	{ok, User} = application:get_env(rest_user),
	{ok, Password} = application:get_env(rest_pass),
	UserPass = User ++ ":" ++ Password,
	BasicAuth = base64:encode_to_string(UserPass),
	Authorization = {"authorization", "Basic " ++ BasicAuth},
	subscriber = ets:new(subscriber, [public, named_table]),
	Data = #statedata{active = Active, mean = Mean,
			deviation = Deviation, uri = Uri,
			id_type = IdType, id_prefix = Prefix, id_n = N,
			auth = Authorization, address = Address},
	{ok, client_request, Data,
			[{state_timeout, rand:uniform(4000), start}]}.

-spec client_request(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>service_request</em> state.
%% @private
%%
client_request(enter = _EventType, client_request = _EventContent, Data) ->
	?LOG_INFO("Begin phase 0: add REST client"),
	{keep_state, Data#statedata{count = 0}};
client_request(enter, client_response, _Data) ->
	keep_state_and_data;
client_request(state_timeout, start,
		#statedata{uri = Uri, auth = Authorization, address = Address} = Data) ->
	Start = erlang:system_time(millisecond),
	Path = "/ocs/v1/client/" ++ inet:ntoa(Address),
	Accept = {"accept", "application/json"},
	Request = {Uri ++ Path, [Authorization, Accept]},
	case httpc:request(get, Request, [], [{sync, false}], tmf) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#statedata{request = RequestId,
					start = Start},
			{next_state, client_response, NewData};
		{error, Reason} ->
			{stop, Reason, Data}
	end;
client_request(state_timeout, post,
		#statedata{address = Address, uri = Uri,
		auth = Authorization} = Data) ->
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
	end.

-spec client_response(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>client_response</em> state.
%% @private
%%
client_response(enter = _EventType, _EventContent, _Data) ->
	keep_state_and_data;
client_response(info,
		{http, {RequestId, {{_, 404, _}, _Headers, _Body}}},
		#statedata{request = RequestId, start = Start} = Data) ->
		NewData = Data#statedata{request = undefined},
	{next_state, client_request, NewData, timeout(Start, post, Data)};
client_response(info = _EventType,
		{http, {RequestId, {{_, StatusCode, _}, _Headers, Body}}},
		#statedata{request = RequestId, start = Start} = Data)
		when StatusCode == 200; StatusCode == 201 ->
	case zj:decode(Body) of
		{ok, #{"id" := Id}} ->
			case inet:parse_address(Id) of
				{ok, Address} ->
					?LOG_INFO("End phase 0: added REST client"),
					NewData = Data#statedata{address = Address},
					{next_state, service_request, NewData,
							timeout(Start, start, NewData)};
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

-spec service_request(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>service_request</em> state.
%% @private
%%
service_request(enter = _EventType, client_response = _EventContent, Data) ->
	?LOG_INFO("Begin phase 1: add service identifiers"),
	{keep_state, Data#statedata{count = 0, cursor = ets:first(subscriber)}};
service_request(enter, service_response, _Data) ->
	keep_state_and_data;
service_request(state_timeout, next,
		#statedata{count = Count, active = Active} = Data)
		when Count > Active ->
	?LOG_INFO("End phase 1: added ~b service identifiers", [Count]),
	Start = erlang:system_time(millisecond),
	{next_state, product_request, Data,  timeout(Start, start, Data)};
service_request(state_timeout, _EventContent,
		#statedata{uri = Uri, auth = Authorization,
		id_prefix = Prefix, id_n = N} = Data) ->
	Start = erlang:system_time(millisecond),
	Path = Uri ++ "/serviceInventoryManagement/v2/service/",
	ContentType = "application/json",
	Accept = {"accept", ContentType},
	RequestHeaders = [Authorization, Accept],
	Chars = [#{"name" => "serviceIdentity", "value" => sub_id(Prefix, N)},
			#{"name" => "serviceAkaK",
				"value" => binary_to_hex(crypto:strong_rand_bytes(16))},
			#{"name" => "serviceAkaOPc",
				"value" => binary_to_hex(crypto:strong_rand_bytes(16))}],
	ServiceSpecificationRef = #{"id" => "1",
			"href" => "/catalogManagement/v2/serviceSpecification/1"},
	RequestBody = zj:encode(#{"serviceCharacteristic" => Chars,
			"serviceSpecification" => ServiceSpecificationRef}),
	Request = {Path, RequestHeaders, ContentType, RequestBody},
	case httpc:request(post, Request, [], [{sync, false}], tmf) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#statedata{request = RequestId, start = Start},
			{next_state, service_response, NewData};
		{error, Reason} ->
			{stop, Reason, Data}
	end.

-spec service_response(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>service_response</em> state.
%% @private
%%
service_response(enter = _EventType, _EventContent, _Data) ->
	keep_state_and_data;
service_response(info = _EventType,
		{http, {RequestId, {{_, 201, _}, _Headers, Body}}},
		#statedata{request = RequestId, count = Count,
		id_type = IdType, start = Start} = Data) ->
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
					Subscriber = #{subscriptionId => Id,
							idType => IdType, k => K, opc => OPc},
					ets:insert(subscription, Subscriber),
					NewData = Data#statedata{request = undefined, count = Count + 1},
					{next_state, service_request, NewData,
							timeout(Start, next, NewData)};
				_ ->
					{stop, bad_service, Data}
			end;
		{Error, _Partial, _Remaining} when Error == error; Error == incomplete ->
			{stop, Error, Data}
	end;
service_response(info = _EventType,
		{http, {RequestId, {{_, StatusCode, _}, _Headers, _Body}}},
		#statedata{request = RequestId} = Data) ->
	{stop, StatusCode, Data};
service_response(info = _EventType, {http, {RequestId, {error, Reason}}},
		#statedata{request = RequestId} = Data) ->
	{stop, Reason, Data}.

-spec product_request(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>product_request</em> state.
%% @private
%%
product_request(enter = _EventType, service_request = _EventContent, Data) ->
	?LOG_INFO("Begin phase 2: add product subscriptions"),
	{keep_state, Data#statedata{count = 0, cursor = ets:first(subscriber)}};
product_request(enter, product_response, _Data) ->
	keep_state_and_data;
product_request(state_timeout, next,
		#statedata{cursor = '$end_of_table', count = Count} = Data) ->
	?LOG_INFO("End phase 2: added ~b product subscriptions", [Count]),
	Start = erlang:system_time(millisecond),
	{next_state, balance_request, Data, timeout(Start, start, Data)};
product_request(state_timeout, _EventContent,
		#statedata{cursor = SubscriberId,
		uri = Uri, auth = Authorization} = Data) ->
	Start = erlang:system_time(millisecond),
	Path = Uri ++ "/productInventoryManagement/v2/product/",
	ContentType = "application/json",
	Accept = {"accept", ContentType},
	RequestHeaders = [Authorization, Accept],
	OfferRef = #{"id" => "Data (10G)",
			"href" => "/catalogManagement/v2/productOffering/Data (10G)"},
	ServiceRef = #{"id" => SubscriberId,
			"href" => "/serviceInventoryManagement/v2/service/" ++ SubscriberId},
	RequestBody = zj:encode(#{"productOffering" => OfferRef,
			"realizingService" => [ServiceRef]}),
	Request = {Path, RequestHeaders, ContentType, RequestBody},
	case httpc:request(post, Request, [], [{sync, false}], tmf) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#statedata{request = RequestId, start = Start},
			{next_state, product_response, NewData};
		{error, Reason} ->
			{stop, Reason, Data}
	end.

-spec product_response(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>product_response</em> state.
%% @private
%%
product_response(enter = _EventType, _EventContent, _Data) ->
	keep_state_and_data;
product_response(info = _EventType,
		{http, {RequestId, {{_, 201, _}, _Headers, Body}}} = _EventContent,
		#statedata{request = RequestId, start = Start,
		cursor = SubscriberId, count = Count} = Data) ->
	case zj:decode(Body) of
		{ok, #{"id" := ProductId} = _Product} ->
			[{_, Subscriber}] = ets:lookup(subscriber, SubscriberId),
			true = ets:insert(subscriber, Subscriber#{productId => ProductId}),
			NewData = Data#statedata{request = undefined,
					cursor = ets:next(subscriber, SubscriberId), count = Count + 1},
			{next_state, product_request, NewData, timeout(Start, next, NewData)};
		{ok, #{}} ->
			{stop, missing_id, Data};
		{Error, _Partial, _Remaining} when Error == error; Error == incomplete ->
			{stop, Error, Data}
	end;
product_response(info = _EventType,
		{http, {RequestId, {{_, StatusCode, _}, _Headers, _Body}}},
		#statedata{request = RequestId} = Data) ->
	{stop, StatusCode, Data};
product_response(info = _EventType, {http, {RequestId, {error, Reason}}},
		#statedata{request = RequestId} = Data) ->
	{stop, Reason, Data}.

-spec balance_request(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>balance_request</em> state.
%% @private
%%
balance_request(enter = _EventType, product_request = _EventContent, Data) ->
	?LOG_INFO("Begin phase 3: add balance buckets"),
	{keep_state, Data#statedata{count = 0, cursor = ets:first(subscriber)}};
balance_request(enter, balance_response, _Data) ->
	keep_state_and_data;
balance_request(state_timeout, next,
		#statedata{cursor = '$end_of_table', count = Count,
		address = Address} = Data) ->
	?LOG_INFO("End phase 3: added ~b balance buckets", [Count]),
	case supervisor:start_child(ocs_bench_diameter_service_fsm_sup, [[Address], []]) of
		{ok, Fsm} ->
			ets:give_away(subscriber, Fsm, []),
			{stop, normal, Data};
		{error, Reason} ->
			{stop, Reason, Data}
	end;
balance_request(state_timeout, _EventContent,
		#statedata{cursor = SubscriberId,
		uri = Uri, auth = Authorization} = Data) ->
	Start = erlang:system_time(millisecond),
	[{_, #{productId := ProductId}}] = ets:lookup(subscriber, SubscriberId),
	Path = Uri ++ "/balanceManagement/v1/balanceAdjustment",
	ContentType = "application/json",
	Accept = {"accept", ContentType},
	RequestHeaders = [Authorization, Accept],
	ProductRef = #{"id" => ProductId,
			"href" => "/productInventoryManagement/v2/product/" ++ ProductId},
	Amount = #{"units" => "cents", "amount" => "100000"},
	RequestBody = zj:encode(#{"name" => "bench",
			"amount" => Amount, "product" => ProductRef}),
	Request = {Path, RequestHeaders, ContentType, RequestBody},
	case httpc:request(post, Request, [], [{sync, false}], tmf) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#statedata{request = RequestId, start = Start},
			{next_state, balance_response, NewData};
		{error, Reason} ->
			{stop, Reason, Data}
	end.

-spec balance_response(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>balance_response</em> state.
%% @private
%%
balance_response(enter = _EventType, _EventContent, _Data) ->
	keep_state_and_data;
balance_response(info = _EventType,
		{http, {RequestId, {{_, 204, _}, _Headers, _Body}}},
		#statedata{request = RequestId, start = Start,
		cursor = SubscriberId, count = Count} = Data) ->
	NewData = Data#statedata{request = undefined,
			cursor = ets:next(subscriber, SubscriberId), count = Count + 1},
	{next_state, balance_request, NewData, timeout(Start, next, NewData)};
balance_response(info = _EventType,
		{http, {RequestId, {{_, StatusCode, _}, _Headers, _Body}}},
		#statedata{request = RequestId} = Data) ->
	{stop, StatusCode, Data};
balance_response(info = _EventType, {http, {RequestId, {error, Reason}}},
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

-spec timeout(Start, EventContent, Data) -> Result
	when
		Start :: pos_integer(),
		EventContent :: term(),
		Data :: #statedata{},
		Result :: [Action],
		Action :: {state_timeout, Time, EventContent},
		Time :: pos_integer().
%% @doc Returns a timeout taking into account the time it took to
%% 	process the current transaction, the configured `mean' rate
%% 	and random `deviation' percentage.
%% @hidden
timeout(Start, EventContent,
		#statedata{mean = Mean, deviation = Deviation}) ->
	End = erlang:system_time(millisecond),
	Time = case (1000 div Mean) - (End - Start) of
		Interval when Interval > 0 ->
			case (Interval * Deviation) div 100 of
				Range when Range > 0 ->
					Interval + (rand:uniform(Range * 2) - Range);
				_Range ->
					0
			end;
		_Interval ->
			0
	end,
	[{state_timeout, Time, EventContent}].

-spec sub_id(Prefix, N) -> [$0..$9]
	when
		Prefix :: string(),
		N :: pos_integer().
%% @doc Generate a subscription identifier.
%% @private
sub_id(Prefix, N) ->
	Charset = lists:seq($0, $9),
	sub_id(Charset, N, lists:reverse(Prefix)).
%% @hidden
sub_id(_, 0, Acc) ->
	lists:reverse(Acc);
sub_id(Charset, N, Acc) ->
	D = lists:nth(rand:uniform(10), Charset),
	sub_id(Charset, N - 1, [D | Acc]).

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

