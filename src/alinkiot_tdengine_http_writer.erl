%%%-------------------------------------------------------------------
%%% @author yqfclid
%%% @copyright (C) 2022, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_http_writer).

-behaviour(gen_server).

-export([
    write/2
]).
-export([
    start_link/1,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
    url,
    authorization,
    pool,
    flush_interval,
    flush_data_size,
    flush_time_ref,
    cache_data
}).


write(Pid, Data) ->
    gen_server:cast(Pid, Data).

%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

start_link(Opts) ->
    gen_server:start_link(?MODULE, [Opts], []).

init([Opts]) ->
    Host = to_binary(proplists:get_value(host, Opts, "127.0.0.1")),
    Port = to_binary(proplists:get_value(port, Opts, 6041)),
    UserName = to_binary(proplists:get_value(username, Opts, "root")),
    Password = to_binary(proplists:get_value(password, Opts, "taosdata")),
    PoolName = proplists:get_value(http_pool, Opts, default),
    FlushInterval = proplists:get_value(flush_interval, Opts, 1000),
    FlushDataSize = proplists:get_value(flush_data_size, Opts, 20),
    Url = <<"http://", Host/binary, ":", Port/binary, "rest/sql">>,
    Authorization = base64:encode(<<UserName/binary, ":", Password/binary>>),
    State = #state{
        url = Url,
        authorization = Authorization,
        pool = PoolName
    }
    {ok, State}.

handle_call(_Request, _From, State = #state{}) ->
    {reply, ok, State}.

handle_cast({insert, Data}, #state{cache_data = CacheData} = State) when length(CacheData) > ->
    {noreply, State};
handle_cast(_Request, State = #state{}) ->
    {noreply, State}.


handle_info({timeout, TimerRef, flush}, #state{cache_data = CacheData} = State) when CacheData =/= []->

    case alinkiot_tdengine:write(CacheData) of

    end,
    {noreply, State#state{CacheData = []}};
handle_info(_Info, State = #state{}) ->
    {noreply, State}.

terminate(_Reason, _State = #state{}) ->
    ok.

code_change(_OldVsn, State = #state{}, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
to_binary(S) when is_atom(S) ->
    atom_to_binary(S);
to_binary(S) when is_list(S) ->
    list_to_binary(S);
to_binary(S) when is_integer(S) ->
    integer_to_binary(S);
to_binary(S) when is_float(S) ->
    float_to_binary(S);
to_binary(S) when is_binary(S) ->
    S;
to_binary(S) ->
    throw({badarg, S}).
