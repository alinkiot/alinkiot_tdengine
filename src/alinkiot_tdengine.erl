%%%-------------------------------------------------------------------
%%% @author kenneth
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 22. 四月 2020 16:38
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine).
-author("kenneth").
-include("alinkiot_tdengine.hrl").
%% API
-export([
    show_database/0,
    create_database/2,
    create_schemas/1,
    create_object/2,
    create_user/2,
    alter_user/2,
    delete_user/1,
    query_object/2,
    batch/1
]).

-export([
    start_workers/0,
    query/1,
    async_query/1
]).

start_workers() ->
    Opts = application:get_all_env(alinkiot_tdengine),
    ecpool_sup:start_pool(alinkiot_tdengine_worker_pool, alinkiot_tdengine_worker, Opts).

show_database() ->
    request(<<"SHOW DATABASES;">>).



create_database(DataBase, Keep) ->
    KeepTime = integer_to_binary(Keep),
    Sql = <<"CREATE DATABASE IF NOT EXISTS ", DataBase/binary, " KEEP ", KeepTime/binary>>,
    request(Sql).



create_schemas(#{<<"tableName">> := TableName, <<"using">> := STbName, <<"tags">> := Tags}) ->
    TagFields = list_to_binary(join(",", Tags, fun format_value/1)),
    Sql = <<"CREATE TABLE IF NOT EXISTS ", TableName/binary, " USING ", STbName/binary, " TAGS (", TagFields/binary, ");">>,
    request(Sql);

create_schemas(#{<<"tableName">> := TableName, <<"fields">> := Fields0} = Schema) ->
    Fields = list_to_binary(join(",", ["createdAt TIMESTAMP"] ++ lists:foldr(
        fun({FieldName, #{<<"type">> := Type}}, Acc) ->
            [<<FieldName/binary, " ", Type/binary>> | Acc]
        end, [], Fields0))),
    TagFields = list_to_binary(join(",", lists:foldr(
        fun({TagName, #{<<"type">> := TType}}, Acc) ->
            [<<TagName/binary, " ", TType/binary>> | Acc]
        end, [], maps:get(<<"tags">>, Schema, [])))),
    Sql =
        case TagFields of
            <<>> ->
                <<"CREATE TABLE IF NOT EXISTS ", TableName/binary, " (", Fields/binary, ");">>;
            _ ->
                <<"CREATE TABLE IF NOT EXISTS ", TableName/binary, " (", Fields/binary, ") TAGS (", TagFields/binary, ");">>
        end,
    request(Sql).


%% 插入
create_object(TableName, #{<<"values">> := Values0} = Object) ->
    Values = format_batch(Object#{ <<"tableName">> => TableName, <<"values">> => [Values0]}),
    Sql = <<"INSERT INTO ", Values/binary, ";">>,
    request(Sql).


%% 查询
query_object(TableName, Query) ->
    Keys = format_keys(Query),
    Order = format_order(Query),
    Limit = format_limit(Query),
    Offset = format_offset(Query),
    Where = format_where(Query),
    Interval = format_interval(Query),
    Fill = format_fill(Query),
    From = format_from(Query),
    Group = format_group(Query),
    Get =
        fun(Keys1) ->
            Tail = list_to_binary(join(" ", [TableName, From, Where], true)),
            Sql = <<"SELECT ", Keys1/binary ," FROM ", Tail/binary>>,
            request(Sql)
        end,
    Fun =
        fun(Keys1) ->
            Tail = list_to_binary(join(" ", [TableName, From, Where, Interval, Fill, Order, Limit, Offset, Group], true)),
            Sql = <<"SELECT ", Keys1/binary, " FROM ", Tail/binary>>,
            request(Sql)
        end,
    case Keys of
        <<"count(*)">> ->
            Get(<<"count(*)">>);
        _ ->
            case re:run(Keys, <<"last_row\\([^\\)]+\\)">>, [{capture,all,binary}]) == nomatch of
                false ->
                    Get(Keys);
                true ->
                    List = re:split(Keys, <<",">>),
                    Is = re:run(Keys, <<"AVG\\([^\\)]+\\)|MAX\\([^\\)]+\\)|MIN\\([^\\)]+\\)">>, [{capture,all,binary}]) == nomatch,
                    case Is andalso lists:member(<<"count(*)">>, List) of
                        true ->
                            case Get(<<"count(*)">>) of
                                {error, Reason} ->
                                    {error, Reason};
                                {ok, _, Result} ->
                                    Keys1 = list_to_binary(join(",", lists:delete(<<"count(*)">>, List), true)),
                                    case Fun(Keys1) of
                                        {ok, Row, Records} ->
                                            {ok, Row, maps:merge(Result, Records)};
                                        {error, Reason} ->
                                            {error, Reason}
                                    end
                            end;
                        false ->
                            Fun(Keys)
                    end
            end
    end.



batch(Requests) when is_list(Requests) ->
    Request1 = list_to_binary(join(" ", [format_batch(Request) || Request <- Requests])),
    Sql = <<"INSERT INTO ", Request1/binary, ";">>,
    request(Sql);
batch(Batch) ->
    Values = format_batch(Batch),
    Sql = <<"INSERT INTO ", Values/binary, ";">>,
    request(Sql).


create_user(UserName, Password) ->
    request(<<"CREATE USER ", UserName/binary, " PASS ‘", Password/binary, "’">>).


delete_user(UserName) ->
    request(<<"DROP USER ", UserName/binary>>).

alter_user(UserName, NewPassword) ->
    request(<<"ALTER USER ", UserName/binary, " PASS ‘", NewPassword/binary, "’">>).


join(Sep, L) -> join(Sep, L, false).
join(Sep, L, Trip) -> join(Sep, L, Trip, fun alinkutil_type:to_binary/1).
join(_Sep, [], _, _) -> [];
join(Sep, [<<>> | T], true, F) -> join(Sep, T, true, F);
join(Sep, [H | T], Trip, F) -> [F(H) | join_prepend(Sep, T, Trip, F)].
join_prepend(_Sep, [], _, _) -> [];
join_prepend(Sep, [<<>> | T], true, F) -> join_prepend(Sep, T, true, F);
join_prepend(Sep, [H | T], Trip, F) -> [Sep, F(H) | join_prepend(Sep, T, Trip, F)].


format_value(V) when is_binary(V) -> <<"'", V/binary, "'">>;
format_value(V) -> alinkutil_type:to_binary(V).

format_column(V) -> alinkutil_type:to_binary(V).


format_db(<<>>) -> <<>>;
format_db(DB) -> <<DB/binary, ".">>.

format_using(_, <<>>) -> <<>>;
format_using(DB, Table) ->
    DB1 = format_db(DB),
    <<" using ", DB1/binary, Table/binary>>.

format_tags(<<>>) -> <<>>;
format_tags(Tags) -> <<" TAGS (", Tags/binary, ")">>.

format_batch(#{<<"tableName">> := TableName, <<"fields">> := Fields0, <<"values">> := Values0} = Batch) ->
    Using = maps:get(<<"using">>, Batch, <<>>),
    Fields = list_to_binary(join(",", Fields0, false, fun format_column/1)),
    Values2 = [list_to_binary("(" ++ join(",", Values1, false, fun format_value/1) ++ ")") || Values1 <- Values0],
    Values = list_to_binary(join(" ", Values2)),
    Using1 = format_using(<<>>, Using),
    Tags = maps:get(<<"tags">>, Batch, []),
    TagFields = format_tags(list_to_binary(join(",", Tags, false, fun format_value/1))),
    <<TableName/binary, Using1/binary, TagFields/binary, " (", Fields/binary, ") VALUES ", Values/binary>>;
format_batch(#{  <<"tableName">> := TableName, <<"values">> := Values0} = Batch) ->
    Using = maps:get(<<"using">>, Batch, <<>>),
    Values2 = [list_to_binary("(" ++ join(",", Values1, false, fun format_value/1) ++ ")") || Values1 <- Values0],
    Values = list_to_binary(join(" ", Values2)),
    Using1 = format_using(<<>>, Using),
    Tags = maps:get(<<"tags">>, Batch, []),
    TagFields = format_tags(list_to_binary(join(",", Tags, false, fun format_value/1))),
    <<TableName/binary, Using1/binary, TagFields/binary, " VALUES ", Values/binary>>.



format_order([], Acc) -> Acc;
format_order([<<"-", Field/binary>> | Other], Acc) ->
    format_order(Other, Acc ++ [<<Field/binary, " DESC">>]);
format_order([<<"+", Field/binary>> | Other], Acc) ->
    format_order([Field | Other], Acc);
format_order([Field | Other], Acc) ->
    format_order(Other, Acc ++ [<<Field/binary, " ASC">>]).
format_order(#{<<"order">> := Order}) when Order =/= <<>>, Order =/= undefined ->
    Order1 = list_to_binary(join(",", format_order(re:split(Order, <<",">>), []))),
    <<"ORDER BY ", Order1/binary>>;
format_order(_) ->
    <<>>.

format_limit(#{<<"limit">> := Limit}) when is_integer(Limit), Limit =/= undefined ->
    L = integer_to_binary(Limit),
    <<"LIMIT ", L/binary>>;
format_limit(_) ->
    <<"LIMIT 5000">>.

format_offset(#{<<"skip">> := Skip}) when Skip =/= undefined, is_integer(Skip) ->
    S = integer_to_binary(Skip),
    <<"OFFSET ", S/binary>>;
format_offset(_) ->
    <<>>.


format_keys(#{<<"keys">> := Keys}) when Keys =/= undefined, Keys =/= <<>> ->
    Keys;
format_keys(_) ->
    <<"*">>.

format_interval(#{<<"interval">> := Interval}) when Interval =/= undefined, is_integer(Interval) ->
    I = integer_to_binary(Interval),
    <<"INTERVAL ", I/binary>>;
format_interval(_) ->
    <<>>.

format_fill(#{<<"fill">> := Value}) when Value =/= <<>>, Value =/= undefined ->
    <<"FILL ", Value/binary>>;
format_fill(_) ->
    <<>>.

format_from(#{<<"from">> := From}) when From =/= <<>>, From =/= undefined ->
    From;
format_from(_) ->
    <<>>.

format_group(#{<<"group">> := Group}) when Group =/= <<>>, Group =/= undefined ->
    <<"GROUP BY ", Group/binary>>;
format_group(_) ->
    <<>>.

format_where([], Acc) ->
    Acc;
format_where([{Field, #{<<"$gt">> := Value}} | Other], Acc) ->
    V = alinkutil_type:to_binary(Value),
    format_where(Other, [<<Field/binary, " > ", V/binary>> | Acc]);
format_where([{Field, #{<<"$gte">> := Value}} | Other], Acc) ->
    V = alinkutil_type:to_binary(Value),
    format_where(Other, [<<Field/binary, " >= ", V/binary>> | Acc]);
format_where([{Field, #{<<"$lt">> := Value}} | Other], Acc) ->
    V = alinkutil_type:to_binary(Value),
    format_where(Other, [<<Field/binary, " < ", V/binary>> | Acc]);
format_where([{Field, #{<<"$gte">> := Value}} | Other], Acc) ->
    V = alinkutil_type:to_binary(Value),
    format_where(Other, [<<Field/binary, " <= ", V/binary>> | Acc]);
format_where([{Field, #{<<"$ne">> := Value}} | Other], Acc) ->
    V = alinkutil_type:to_binary(Value),
    format_where(Other, [<<Field/binary, " <> ", V/binary>> | Acc]);
format_where([{Field, #{<<"$regex">> := Value}} | Other], Acc) ->
    V = alinkutil_type:to_binary(Value),
    format_where(Other, [<<Field/binary, " LIKE '", V/binary, "'">> | Acc]);
format_where([{Field, Value} | Other], Acc) ->
    V = alinkutil_type:to_binary(Value),
    format_where(Other, [<<Field/binary, " = '", V/binary, "'">> | Acc]).
format_where(#{<<"where">> := Where}) when Where =/= undefined, Where =/= <<>> ->
    Where1 =
        case is_list(Where) of
            true ->
                format_where(Where, []);
            false when is_map(Where) ->
                format_where(maps:to_list(Where), [])
        end,
    case list_to_binary(lists:join(" AND ", lists:reverse(Where1))) of
        <<>> ->
            <<>>;
        Where2 ->
            <<"WHERE ", Where2/binary>>
    end;
format_where(_) ->
    <<>>.



request(Sql) ->
    case query(Sql) of
        {ok, Row, Result} ->
            {ok, Row, format_result(Result)};
        {error, Reason} ->
            logger:error("Execute Fail ~p ~p", [Sql, Reason]),
            {error, Reason}
    end.


format_result(#{<<"count(*)">> := Count} = R) -> R#{<<"count">> => Count};
format_result(R) -> R.

query(Sql) ->
    ecpool:with_client(alinkiot_tdengine_worker_pool, fun(Pid) -> alinkiot_tdengine_worker:query(Pid, Sql) end).

async_query(Sql) ->
    ecpool:with_client(alinkiot_tdengine_worker_pool, fun(Pid) -> alinkiot_tdengine_worker:async_query(Pid, Sql) end).
