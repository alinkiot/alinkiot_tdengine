%%%-------------------------------------------------------------------
%%% @author yqfclid
%%% @copyright (C) 2022
%%% @doc
%%%
%%% @end
%%% Created : 20. 9月 2022 下午7:31
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_writer).
-author("yqfclid").

%% API
-export([
    start/0,
    start/2,
    start_writer/2,
    stop_writer/1,
    lookup_writer/1,
    write/2,
    set_client_writer/2
]).

-include("alinkiot_tdengine.hrl").
%%%===================================================================
%%% API
%%%===================================================================
start() ->
    WriteOptions = application:get_env(alinkiot_tdengine, writer_options, []),
    Mods = [],
    lists:foreach(fun(Mod) -> start(Mod, WriteOptions) end, Mods).

start(Mod, WriterOpts) ->
    {ok, ProductId} = proplists:get_value(alinkiot_td_writer, Mod:module_info(attributes)),
    Mod:start(WriterOpts),
    WriterName = writer_name(ProductId),
    NWriterOpts = [{http_pool, WriterName}|WriterOpts],
    {ok, _} = start_writer(WriterName, NWriterOpts),
    ok.


start_writer(WriterName, Opts) ->
    ecpool_sup:start_pool(WriterName, alinkiot_tdengine_http_writer, Opts).

%% stop pool
stop_writer(WriterName) ->
    ecpool_sup:stop_pool(WriterName).


set_client_writer(ClientId, ProductId) ->
    WriterName = writer_name(ProductId),
    ets:insert(?WRITER_TAB, {ClientId, WriterName }).


lookup_writer(ClientId) ->
    case ets:lookup(?WRITER_TAB, ClientId) of
        {ok, [{ClientId, Writer}]} ->
            {ok, Writer};
        [] ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.



write(WriterName, Msg) ->
    F = fun(Pid) -> alinkiot_tdengine_http_writer:insert(Pid, Msg) end,
    ecpool:with_client(WriterName, F).
%%%===================================================================
%%% Application callbacks
%%%===================================================================
writer_name(WriterName) ->
    {alinkiot_tdengine, WriterName}.