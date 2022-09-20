%%%-------------------------------------------------------------------
%%% @author yqfclid
%%% @copyright (C) 2022, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_http_writer).

-behaviour(gen_server).

-export([
    start_pool/2,
    stop_pool/1,
    insert/2,
    connect/1
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
    authorization,
    pool,
    flush_interval,
    flush_data_size,
    flush_time_ref,
    cache_datas,
    data_parse_mod
}).

start_pool(PoolName, Opts) ->
    ecpool_sup:start_pool(PoolName, ?MODULE, Opts).

%% stop pool
stop_pool(PoolName) ->
    ecpool_sup:stop_pool(PoolName).

insert(Pid, Data) ->
    gen_server:cast(Pid, Data).

connect(Opts) ->
    gen_server:start_link(?MODULE, [Opts], []).


%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

init([Opts]) ->
    Host = to_binary(proplists:get_value(host, Opts, "127.0.0.1")),
    Port = to_binary(proplists:get_value(port, Opts, 6041)),
    UserName = to_binary(proplists:get_value(username, Opts, "root")),
    Password = to_binary(proplists:get_value(password, Opts, "taosdata")),
    PoolName = proplists:get_value(pool, Opts, default),
    FlushInterval = proplists:get_value(flush_interval, Opts, 0),
    FlushDataSize = proplists:get_value(flush_data_size, Opts, 0),
    DataBase = proplists:get_value(database, Opts, <<>>),
    Url = <<"http://", Host/binary, ":", Port/binary, "rest/sql/", DataBase/binary>>,
    Token = base64:encode(<<UserName/binary, ":", Password/binary>>),
    Authorization = <<"Basic ", Token/binary>>,
    DataParseMod = proplists:get_value(data_parse_mod, Opts, undefined),
    hackney_pool:start_pool(PoolName, [{max_connections, 4}]),
    State = #state{
        url = Url,
        authorization = Authorization,
        pool = PoolName,
        flush_interval = FlushInterval,
        flush_data_size = FlushDataSize,
        flush_time_ref = start_timer(FlushInterval),
        cache_datas = [],
        data_parse_mod = DataParseMod
    },
    {ok, State}.

handle_call(_Request, _From, State = #state{}) ->
    {reply, ok, State}.

handle_cast({insert, Data}, #state{cache_datas = CacheDatas,
                                   flush_data_size = FlushDataSize} = State) when length(CacheDatas) >= FlushDataSize - 1 ->
    write([Data|CacheDatas], State),
    {noreply, State#state{cache_datas = []}};
handle_cast({insert, Data}, #state{cache_datas = CacheDatas} = State) ->
    {noreply, State#state{cache_datas = [Data|CacheDatas]}};
handle_cast(_Request, State = #state{}) ->
    {noreply, State}.


handle_info({timeout, TimerRef, flush}, #state{cache_datas = CacheDatas,
                                               flush_time_ref = TimerRef,
                                                flush_interval = FlushInterval} = State) when CacheDatas =/= []->
    write(CacheDatas, State),
    {noreply, State#state{cache_datas = [], flush_time_ref = start_timer(FlushInterval)}};
handle_info(_Info, State = #state{}) ->
    {noreply, State}.

terminate(_Reason, _State = #state{}) ->
    ok.

code_change(_OldVsn, State = #state{}, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
start_timer(0) -> erlang:make_ref();
start_timer(FlushInterval) -> timer:start_timer(FlushInterval, self(), flush).


write(Datas, State) ->
    #state{url = Url,
           authorization = Authorization,
           pool = PoolName,
           data_parse_mod = Mod} = State,
    case catch Mod:parse(Datas) of
        Sql when is_list(Sql) orelse is_binary(Sql) ->
            QueryOpts =
                #{
                    pool => PoolName,
                    authorization => Authorization,
                    retry => 3
                },
            case alinkiot_tdengine_rest:query(Url, Sql, QueryOpts) of
                {ok, _} ->
                    ok;
                {error, Reason} ->
                    logger:error("Data ~p State ~p send data to tdengine failed:~p", [Datas, State, Reason])
            end;
        Err ->
            logger:error("mod ~p parse datas ~p failed: ~p", [Mod, Datas, Err])
    end.


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
