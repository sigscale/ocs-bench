%%% ocs_bench_diameter_ro_fsm.erl
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
%%% 	module implements a transaction handler for DIAMETER Ro in the
%%% 	{@link //ocs_bench. ocs_bench} application.
%%%
-module(ocs_bench_diameter_ro_fsm).
-copyright('Copyright (c) 2020 SigScale Global Inc.').

-behaviour(gen_statem).

%% export the ocs_bench_diameter_ro_fsm API
-export([]).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states. 
-export([transaction/3]).

-type state() :: transaction.

-record(statedata,
		{active :: pos_integer(),
		mean :: pos_integer(),
		deviation :: 0..100,
		service :: term()}).
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
	[Service] = diameter:get_services(),
	{ok, transaction, #statedata{active = Active, mean = Mean,
			deviation = Deviation, service = Service}, rand:uniform(4000)}.

-spec transaction(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>transaction</em> state.
%% @private
%%
transaction(timeout = _EventType, _EventContent, #statedata{} = Data) ->
	Start = erlang:system_time(millisecond),
	{next_state, transaction, Data, timeout(Start, Data)}.

-spec handle_event(EventType, EventContent, State, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		State :: state(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(State).
%% @doc Handles events received in the any state.
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

