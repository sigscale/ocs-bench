%%% ocs_bench_diameter_ro_fsm.erl
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
%%% 	module implements a transaction handler for DIAMETER Ro in the
%%% 	{@link //ocs_bench. ocs_bench} application.
%%%
-module(ocs_bench_diameter_ro_fsm).
-copyright('Copyright (c) 2020-2025 SigScale Global Inc.').

-behaviour(gen_statem).

%% export the ocs_bench_diameter_ro_fsm API
-export([]).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([ccr/3, cca/3]).

-include_lib("kernel/include/logger.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include_lib("ocs/include/diameter_gen_3gpp.hrl").
-include_lib("ocs/include/diameter_gen_cc_application_rfc4006.hrl").
-include_lib("ocs/include/diameter_gen_3gpp_ro_application.hrl").

-define(RO_APPLICATION_ID, 4).
-define(RO_APPLICATION, ocs_diameter_3gpp_ro_application).

-type state() :: ccr | cca.

-record(statedata,
		{active :: pos_integer(),
		mean :: pos_integer(),
		deviation :: 0..100,
		rate_groups :: [pos_integer()],
		service :: term(),
		start :: undefined | pos_integer(),
		cursor :: undefined | term() | '$end_of_table',
		count = 0 :: non_neg_integer(),
		orig_host :: binary(),
		orig_realm :: binary(),
		dest_realm :: binary(),
		session :: undefined | string()}).
-type statedata() :: #statedata{}.

%%----------------------------------------------------------------------
%%  The ocs_bench_diameter_ro_fsm API
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  The ocs_bench_diameter_ro_fsm gen_statem callbacks
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
init(_Args) ->
	{ok, Active} = application:get_env(active),
	{ok, Mean} = application:get_env(mean),
	{ok, Deviation} = application:get_env(deviation),
	{ok, RateGroups} = application:get_env(rate_groups),
	[Service | _] = diameter:services(),
	[Connection | _] = diameter:service_info(default, connections),
	{_, Caps} = lists:keyfind(caps, 1, Connection),
	{_, {OriginHost, _DestinationHost}} = lists:keyfind(origin_host, 1, Caps),
	{_, {OriginRealm, DestinationRealm}} = lists:keyfind(origin_realm, 1, Caps),
	{ok, ccr, #statedata{active = Active, mean = Mean,
			rate_groups = RateGroups,
			deviation = Deviation, service = Service,
			orig_host = OriginHost, orig_realm = OriginRealm,
			dest_realm = DestinationRealm},
			[{state_timeout, rand:uniform(4000), start}]}.

-spec ccr(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>ccr</em> state.
%% @private
%%
ccr(enter = _EventType, ccr = _EventContent, Data) ->
	?LOG_NOTICE("Begin phase 4: start user sessions"),
	{keep_state, Data#statedata{count = 0, cursor = ets:first(subscriber)}};
ccr(enter, _EventContent,
		#statedata{cursor = '$end_of_table'} = Data) ->
	{keep_state, Data#statedata{cursor = ets:first(subscriber)}};
ccr(enter, _EventContent, _Data) ->
	keep_state_and_data;
ccr(state_timeout, _EventContent,
		#statedata{cursor = '$end_of_table'} = Data) ->
	{stop, normal, Data};
ccr(state_timeout, _EventContent,
		#statedata{cursor = SubscriberId,
		service = Service, rate_groups = RateGroups,
		orig_host = OriginHost, orig_realm = OriginRealm,
		dest_realm = DestinationRealm} = Data) ->
	Start = erlang:system_time(millisecond),
	case ets:lookup(subscriber, SubscriberId) of
		[{_, #{pending := true} = _Subscriber}] ->
			NewData = Data#statedata{cursor = ets:next(subscriber, SubscriberId)},
			{keept_state, NewData, timeout(Start, next, NewData)};
		[{_, #{} = Subscriber}] ->
			SubId = #'3gpp_ro_Subscription-Id'{'Subscription-Id-Data' = SubscriberId},
			Request = #'3gpp_ro_CCR'{'User-Name' = [SubscriberId],
					'Origin-Host' = OriginHost,
					'Origin-Realm' = OriginRealm,
					'Destination-Realm' = DestinationRealm,
					'Auth-Application-Id' = ?RO_APPLICATION_ID,
					'Service-Context-Id' = "32251@3gpp.org",
					'Multiple-Services-Indicator' = [?'3GPP_MULTIPLE-SERVICES-INDICATOR_MULTIPLE_SERVICES_SUPPORTED'],
					'Service-Information' = [#'3gpp_ro_Service-Information'{
							'PS-Information' = [#'3gpp_ro_PS-Information'{
									'3GPP-SGSN-MCC-MNC' = ["001001"]}]}]},
			MaxRequest = rand:uniform(25),
			{Session, Request1} = case maps:find(requestNumber, Subscriber) of
				error ->
					RequestNumber = 0,
					SessionId = list_to_binary(diameter:session_id(binary_to_list(OriginHost))),
					ets:insert(subscriber, {SubscriberId, Subscriber#{pending => true,
							session => SessionId, requestNumber => RequestNumber}}),
					RSU = #'3gpp_ro_Requested-Service-Unit'{},
					MSCC = [#'3gpp_ro_Multiple-Services-Credit-Control'{
							'Service-Identifier' = [1],
							'Rating-Group' = [RG],
							'Requested-Service-Unit' = [RSU]} || RG <- RateGroups],
					{SessionId, Request#'3gpp_ro_CCR'{'Session-Id' = SessionId,
							'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
							'CC-Request-Number' = RequestNumber,
							'Subscription-Id' = [sub_id(maps:get(idType, Subscriber), SubId)],
							'Multiple-Services-Credit-Control' = MSCC}};
				{ok, RequestNumber} when RequestNumber < MaxRequest ->
					F = fun({RG, Reserve}, {Acc1, Acc2}) ->
							UsuSize = rand:uniform(Reserve),
							USU = #'3gpp_ro_Used-Service-Unit'{'CC-Total-Octets' = [UsuSize]},
							RSU = #'3gpp_ro_Requested-Service-Unit'{},
							MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
									'Service-Identifier' = [1], 'Rating-Group' = [RG],
									'Used-Service-Unit' = [USU], 'Requested-Service-Unit' = [RSU]},
							{[MSCC | Acc1], [{RG, Reserve - UsuSize} | Acc2]}
					end,
					{MSCC, Reserved} = lists:foldl(F, {[], []},
							maps:get(reserved, Subscriber)),
					NewRequestNumber = RequestNumber + 1,
					SessionId = maps:get(session, Subscriber),
					NewSubscriber = Subscriber#{pending := true,
							requestNumber := NewRequestNumber,
							reserved => lists:reverse(Reserved)},
					ets:insert(subscriber, {SubscriberId, NewSubscriber}),
					{SessionId, Request#'3gpp_ro_CCR'{'Session-Id' = SessionId,
							'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
							'CC-Request-Number' = NewRequestNumber,
							'Subscription-Id' = [sub_id(maps:get(idType, Subscriber), SubId)],
							'Multiple-Services-Credit-Control' = lists:reverse(MSCC)}};
				{ok, RequestNumber} when RequestNumber >= MaxRequest ->
					F = fun({RG, Reserve}, {Acc1, Acc2}) ->
							UsuSize = rand:uniform(Reserve),
							USU = #'3gpp_ro_Used-Service-Unit'{'CC-Total-Octets' = [UsuSize]},
							MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
									'Service-Identifier' = [1], 'Rating-Group' = [RG],
									'Used-Service-Unit' = [USU]},
							{[MSCC | Acc1], [{RG, Reserve - UsuSize} | Acc2]}
					end,
					{MSCC, Reserved} = lists:foldl(F, {[], []},
							maps:get(reserved, Subscriber)),
					NewRequestNumber = RequestNumber + 1,
					SessionId = maps:get(session, Subscriber),
					NewSubscriber = Subscriber#{pending := true,
							requestNumber := NewRequestNumber,
							reserved => lists:reverse(Reserved)},
					ets:insert(subscriber, {SubscriberId, NewSubscriber}),
					{SessionId, Request#'3gpp_ro_CCR'{'Session-Id' = SessionId,
							'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
							'CC-Request-Number' = NewRequestNumber,
							'Subscription-Id' = [sub_id(maps:get(idType, Subscriber), SubId)],
							'Multiple-Services-Credit-Control' = lists:reverse(MSCC)}}
			end,
			case diameter:call(Service, ?RO_APPLICATION, Request1,
					[detach, {extra, [self()]}]) of
				ok ->
					NewData = Data#statedata{start = Start, session = Session},
					{next_state, cca, NewData};
				{error, Reason} ->
					{stop, Reason, Data}
			end
	end.

-spec cca(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>cca</em> state.
%% @private
%%
cca(enter = _EventType, _EventContent, _Data) ->
	keep_state_and_data;
cca(cast, {ok, #'3gpp_ro_CCA'{'Session-Id' = Session,
		'CC-Request-Type' = RequestType,
		'Multiple-Services-Credit-Control' = MSCC,
		'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'} = _CCA},
		#statedata{session = Session, start = Start, cursor = SubscriberId,
		count = Count} = Data) when
		RequestType == ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST';
		RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST' ->
	[{_, Subscriber}] = ets:lookup(subscriber, SubscriberId),
	F = fun(M, Acc) ->
			[RG] = M#'3gpp_ro_Multiple-Services-Credit-Control'.'Rating-Group',
			[GSU] = M#'3gpp_ro_Multiple-Services-Credit-Control'.'Granted-Service-Unit',
			[GsuSize] = GSU#'3gpp_ro_Granted-Service-Unit'.'CC-Total-Octets',
			[{RG, GsuSize} | Acc]
	end,
	Reserved = lists:foldl(F, [], MSCC),
	NewSubscriber = Subscriber#{pending := false,
			reserved => lists:reverse(Reserved)},
	ets:insert(subscriber, {SubscriberId, NewSubscriber}),
	NewData = Data#statedata{session = undefined,
			cursor = ets:next(subscriber, SubscriberId), count = Count + 1},
	{next_state, ccr, NewData, timeout(Start, next, NewData)};
cca(cast, {ok, #'3gpp_ro_CCA'{'Session-Id' = Session,
		'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
		'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'} = _CCA},
		#statedata{session = Session, start = Start, cursor = SubscriberId,
		count = Count} = Data) ->
	[{_, Subscriber}] = ets:lookup(subscriber, SubscriberId),
	NewSubscriber = maps:remove(reserved,
			maps:remove(session, maps:remove(requestNumber, Subscriber))),
	ets:insert(subscriber, {SubscriberId, NewSubscriber#{pending := false}}),
	NewData = Data#statedata{session = undefined,
			cursor = ets:next(subscriber, SubscriberId), count = Count + 1},
	{next_state, ccr, NewData, timeout(Start, next, NewData)};
cca(cast, {ok, #'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED'} = _CCA},
		#statedata{start = Start, cursor = SubscriberId, count = Count} = Data) ->
	NewData = Data#statedata{session = undefined,
			cursor = ets:next(subscriber, SubscriberId), count = Count + 1},
	ets:delete(subscriber, SubscriberId),
	{next_state, ccr, NewData, timeout(Start, next, NewData)};
cca(cast, {ok, #'3gpp_ro_CCA'{'Result-Code' = ResultCode}}, Data) ->
	{stop, ResultCode, Data};
cca(cast, {error, Reason}, Data) ->
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

-spec sub_id(Type, R) -> R
	when
		Type :: imsi | msisdn,
		R :: #'3gpp_ro_Subscription-Id'{}.
%% @doc Add `Subscription-Id' type. 
%% @hidden
sub_id(imsi, R) ->
	R#'3gpp_ro_Subscription-Id'{'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI'};
sub_id(msisdn, R) ->
	R#'3gpp_ro_Subscription-Id'{'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164'}.

