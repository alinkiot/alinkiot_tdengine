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
    start_writer/2,
    stop_writer/1,
    insert/2
]).

%%%===================================================================
%%% API
%%%===================================================================
start_writer(WriterName, Opts) ->
    ecpool_sup:start_pool(WriterName, alinkiot_tdengine_http_writer, Opts).

%% stop pool
stop_writer(WriterName) ->
    ecpool_sup:stop_pool(WriterName).

insert(WriterName, Data) ->
    F = fun(Pid) -> alinkiot_tdengine_http_writer:insert(Pid, Data) end,
    ecpool:with_client(WriterName, F).
%%%===================================================================
%%% Application callbacks
%%%===================================================================