%%%-------------------------------------------------------------------
%%% @author yqfclid
%%% @copyright (C) 2022, <COMPANY>
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_worker).

-behaviour(gen_server).

-export([
    async_query/2,
    query/2,
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
    authorization
}).


async_query(Pid, Query) ->
    gen_server:cast(Pid, {query, Query}).

query(Pid, Query) ->
    gen_server:call(Pid, {query, Query}).

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
    DataBase = alinkutil_type:to_binary(proplists:get_value(database, Opts, <<>>)),
    Url = alinkiot_tdengine_rest:build_url(Host, Port, DataBase),
    Token = base64:encode(<<UserName/binary, ":", Password/binary>>),
    Authorization = <<"Basic ", Token/binary>>,
    State = #state{
        url = Url,
        authorization = Authorization
    },
    {ok, State}.

handle_call({query, Query}, _From, State) ->
    {reply, do_query(Query, State), State};
handle_call(_Request, _From, State = #state{}) ->
    {reply, ok, State}.

handle_cast({query, Query}, State) ->
    case do_query(Query, State) of
        {ok, _, _} ->
            ok;
        {error, Reason} ->
            logger:error("query ~p State ~p query from tdengine failed:~p", [Query, State, Reason])
    end,
    {noreply, State};
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
do_query(Query, State) ->
    #state{url = Url,
           authorization = Authorization} = State,
    QueryOpts =
        #{
            authorization => Authorization,
            retry => 5
        },
    alinkiot_tdengine_rest:query(Url, Query, QueryOpts).
