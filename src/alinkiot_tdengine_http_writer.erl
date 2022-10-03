%%%-------------------------------------------------------------------
%%% @author yqfclid
%%% @copyright (C) 2022, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_http_writer).

-behaviour(gen_server).

-export([
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
    flush_msg_len,
    flush_time_ref,
    cache_msgs,
    handler_mod
}).

insert(Pid, Message) ->
    gen_server:cast(Pid, Message).

connect(Opts) ->
    gen_server:start_link(?MODULE, [Opts], []).


%%%===================================================================
%%% Spawning and gen_server implementation
%%%===================================================================

init([Opts]) ->
    Host = alinkutil_type:to_binary(proplists:get_value(host, Opts, "127.0.0.1")),
    Port = alinkutil_type:to_binary(proplists:get_value(port, Opts, 6041)),
    UserName = alinkutil_type:to_binary(proplists:get_value(username, Opts, "root")),
    Password = alinkutil_type:to_binary(proplists:get_value(password, Opts, "taosdata")),
    PoolName = proplists:get_value(http_pool, Opts, default),
    FlushInterval = proplists:get_value(flush_interval, Opts, 0),
    FlushMsgLen = proplists:get_value(flush_msg_len, Opts, 0),
    DataBase = alinkutil_type:to_binary(proplists:get_value(database, Opts, <<>>)),
    Url = alinkiot_tdengine_rest:build_url(Host, Port, DataBase),
    Token = base64:encode(<<UserName/binary, ":", Password/binary>>),
    Authorization = <<"Basic ", Token/binary>>,
    HandlerMod = proplists:get_value(handler_mod, Opts, undefined),
    hackney_pool:start_pool(PoolName, [{max_connections, 4}]),
    State = #state{
        url = Url,
        authorization = Authorization,
        pool = PoolName,
        flush_interval = FlushInterval,
        flush_msg_len = FlushMsgLen,
        flush_time_ref = start_timer(FlushInterval),
        cache_msgs = [],
        handler_mod = HandlerMod
    },
    {ok, State}.

handle_call(_Request, _From, State = #state{}) ->
    {reply, ok, State}.

handle_cast({insert, Msg}, #state{cache_msgs = CacheMsgs,
                                  flush_msg_len = FlushMsgLen} = State) when length(CacheMsgs) >= FlushMsgLen - 1 ->
    write([Msg|CacheMsgs], State),
    {noreply, State#state{cache_msgs = []}};
handle_cast({insert, Data}, #state{cache_msgs = CacheMsgs} = State) ->
    {noreply, State#state{cache_msgs = [Data|CacheMsgs]}};
handle_cast(_Request, State = #state{}) ->
    {noreply, State}.


handle_info({timeout, TimerRef, flush}, #state{cache_msgs = CacheMsgs,
                                               flush_time_ref = TimerRef,
                                               flush_interval = FlushInterval} = State) when CacheMsgs =/= []->
    write(CacheMsgs, State),
    {noreply, State#state{cache_msgs = [], flush_time_ref = start_timer(FlushInterval)}};
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


write(Msgs, State) ->
    #state{url = Url,
           authorization = Authorization,
           pool = PoolName,
           handler_mod = Mod} = State,
    case catch Mod:parse_messages_to_sql(Msgs) of
        Sql when is_list(Sql) orelse is_binary(Sql) ->
            QueryOpts =
                #{
                    pool => PoolName,
                    authorization => Authorization,
                    retry => 3
                },
            case alinkiot_tdengine_rest:query(Url, Sql, QueryOpts) of
                {ok, _, _} ->
                    ok;
                {error, Reason} ->
                    logger:error("Data ~p State ~p send data to tdengine failed:~p", [Msgs, State, Reason])
            end;
        Err ->
            logger:error("mod ~p parse datas ~p failed: ~p", [Mod, Msgs, Err])
    end.
