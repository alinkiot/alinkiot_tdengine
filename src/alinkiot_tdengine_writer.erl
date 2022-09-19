%%%-------------------------------------------------------------------
%%% @author yqfclid
%%% @copyright (C) 2022, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_writer).

-behaviour(gen_server).

-export([
    start_link/1,
    write/1
]).
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
    url,
    username,
    password,
    pool,
    flush_interval,
    flush_data_length,
    flush_time_ref
}).


write(Data) ->
    ok.

%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [Opts], []).

init([Opts]) ->
    {ok, #state{}}.

handle_call(_Request, _From, State = #state{}) ->
    {reply, ok, State}.

handle_cast(_Request, State = #state{}) ->
    {noreply, State}.

handle_info(_Info, State = #state{}) ->
    {noreply, State}.

terminate(_Reason, _State = #state{}) ->
    ok.

code_change(_OldVsn, State = #state{}, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
