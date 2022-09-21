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
    start/0,
    parse/1
]).

-include_lib("emqx/include/emqx.hrl").
%%%===================================================================
%%% API
%%%===================================================================
start() ->
    WriteOptions = application:get_env(alinkiot_tdengine, writer_options, []),
    Host = proplists:get_value(host, WriteOptions, "127.0.0.1"),
    Port = proplists:get_value(host, WriteOptions, 6041),
    UserName = proplists:get_value(username, WriteOptions, "root"),
    Password = proplists:get_value(password, WriteOptions, "taosdata"),
    CreateDB = <<"create database if not exist test;">>,
    CreateStable =  <<"create stable if not exist test.test_stable(ts timestamp, v1 float, v2 tindyint)  tags (f1 tindyint);">>,
    {ok, _} = alinkiot_tdengine_rest:simple_query(Host, Port, UserName, Password, CreateDB),
    {ok, _} = alinkiot_tdengine_rest:simple_query(Host, Port, UserName, Password, CreateStable).


parse(Msgs) ->
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
    STable = <<"test">>,
    Time = integer_to_binary(Ts),
    V1 = float_to_binary(maps:get(<<"v1">>, Payload)),
    V2 = integer_to_binary(maps:get(<<"v2">>, Payload)),
    F1 = integer_to_binary(maps:get(<<"f1">>, Payload)),
    <<From/binary, " using ", STable/binary, "tags(", V1/binary,
        ") values(", Time/binary, ",", V1/binary, ",", V2/binary, ")\n">>.
