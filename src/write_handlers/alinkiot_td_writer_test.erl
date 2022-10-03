%%%-------------------------------------------------------------------
%%% @author yqfclid
%%% @copyright (C) 2022, yuqinfeng17@gmail.com
%%% @doc
%%%
%%% @end
%%% Created : 21. 9月 2022 下午3:59
%%%-------------------------------------------------------------------
-module(alinkiot_td_writer_test).
-author("yqfclid").

-alinkiot_td_writer(test).

%% API
-export([
    start/1,
    parse_messages_to_sql/1
]).

-include("emqx.hrl").
%%%===================================================================
%%% API
%%%===================================================================
start(WriteOptions) ->
    Host = proplists:get_value(host, WriteOptions, "127.0.0.1"),
    Port = proplists:get_value(port, WriteOptions, 6041),
    UserName = proplists:get_value(username, WriteOptions, "root"),
    Password = proplists:get_value(password, WriteOptions, "taosdata"),
    Database = proplists:get_value(database, WriteOptions, "alinkiot"),
    CreateDB = <<"create database if not exists alinkiot;">>,
    CreateStable =  <<"create stable if not exists alinkiot.test_stable(ts timestamp, v1 float, v2 tinyint)  tags (f1 tinyint);">>,
    {ok, _, _} = alinkiot_tdengine_rest:simple_query(Host, Port, UserName, Password, Database, CreateDB),
    {ok, _, _} = alinkiot_tdengine_rest:simple_query(Host, Port, UserName, Password, Database, CreateStable).


parse_messages_to_sql(Msgs) ->
    SqlContent =
        lists:foldl(
            fun(Msg, Acc) ->
                SqlC = parse_message(Msg),
                <<Acc/binary, SqlC/binary>>
        end, <<>>, Msgs),
    SqlHeader = <<"insert into ">>,
    <<SqlHeader/binary, SqlContent/binary, ";">>.
%%%===================================================================
%%% Internal functions
%%%===================================================================
parse_message(#message{payload = Payload, from = From, timestamp = Ts}) ->
    PayloadMap = jiffy:decode(Payload, [return_maps]),
    STable = <<"test">>,
    Time = integer_to_binary(Ts),
    V1 = float_to_binary(maps:get(<<"v1">>, PayloadMap, 0)),
    V2 = integer_to_binary(maps:get(<<"v2">>, PayloadMap, 0)),
    F1 = integer_to_binary(maps:get(<<"f1">>, PayloadMap, 0)),
    <<From/binary, " using ", STable/binary, "tags(", F1/binary,
        ") values(", Time/binary, ",", V1/binary, ",", V2/binary, ")\n">>.
