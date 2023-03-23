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
    init_alink/0,
    show_database/0,
    get_schema/1,
    create_database/2,
    create_schema/1,
    create_alink_schema/2,
    del_columns/2,
    del_column/2,
    add_columns/2,
    add_column/2,
    query_history/4,
    query_alink/1,

    insert_object/2,
    create_user/2,
    alter_user/2,
    delete_user/1,
    query_object/2,
    batch/1,
    request/1
]).

%%%===================================================================
%%% API
%%%===================================================================
init_alink() ->
    case application:get_env(alinkiot_tdengine, database) of
        {ok, DB} ->
            create_database(DB, 3650);
        undefined ->
            ok
    end.


show_database() ->
    request(<<"SHOW DATABASES;">>).



create_database(DataBase, Keep) ->
    KeepTime = alinkutil_type:to_binary(Keep),
    Sql = <<"CREATE DATABASE IF NOT EXISTS ", DataBase/binary, " KEEP ", KeepTime/binary>>,
    request(Sql).

get_schema(Table) ->
    Sql = <<"describe ", Table/binary>>,
    request(Sql).

%% tags => [#{name => tagname, type => tagtype},....]
create_schema(#{<<"table">> := _TableName, <<"using">> := _STbName, <<"tags">> := []}) ->
    {error, tags_empty};
create_schema(#{<<"table">> := TableName, <<"using">> := STbName, <<"tags">> := Tags}) ->
    TableNameB = alinkutil_type:to_binary(TableName),
    STbNameB = alinkutil_type:to_binary(STbName),
    Sql0 = <<"create table if not exists ", TableNameB/binary, " using ", STbNameB/binary, "(">>,
    {Sql1, Sql3} = create_subtable_fields_bin(Tags),
    Sql2 = <<") tags(">>,
    Sql4 = <<")">>,
    Sql = <<Sql0/binary, Sql1/binary, Sql2/binary, Sql3/binary, Sql4/binary>>,
    request(Sql);
create_schema(#{<<"fields">> := []}) ->
    {error, fields_empty};
create_schema(#{<<"stable">> := TableName, <<"fields">> := Fields} = Schema) ->
    TableNameB = alinkutil_type:to_binary(TableName),
    Sql0 = <<"create stable if not exists ", TableNameB/binary, " (time TIMESTAMP">>,
    Sql1 = create_table_fields_bin(Fields),
    Sql =
        case maps:get(<<"tags">>, Schema, []) of
            [] ->
                <<Sql0/binary, Sql1/binary, ")">>;
            Tags ->
                Sql2 = create_table_tags_bin(Tags),
                <<Sql0/binary, Sql1/binary, ") tags (", Sql2/binary, ")">>
        end,
    request(Sql);
create_schema(#{<<"table">> := TableName, <<"fields">> := Fields} = Schema) ->
    TableNameB = alinkutil_type:to_binary(TableName),
    Sql0 = <<"create table if not exists ", TableNameB/binary, " (time TIMESTAMP">>,
    Sql1 = create_table_fields_bin(Fields),
    Sql =
        case maps:get(<<"tags">>, Schema, []) of
            [] ->
                <<Sql0/binary, Sql1/binary, ")">>;
            Tags ->
                Sql2 = create_table_tags_bin(Tags),
                <<Sql0/binary, Sql1/binary, ") tags (", Sql2/binary, ")">>
        end,
    request(Sql).


create_alink_schema(ProductId, ThingInfo) ->
    ProductIdB = alinkutil_type:to_binary(ProductId),
    STable = <<"alinkiot_", ProductIdB/binary>>,
    FilterThingInfo =
        lists:filter(
            fun(#{<<"name">> := Name}) ->
                Name =/= <<"time">>
        end, ThingInfo),
    Tags = [
        #{<<"name">> => <<"addr">>, <<"type">> => <<"string">>},
        #{<<"name">> => <<"product_id">>, <<"type">> => <<"int">>}
    ],
    CreateSchemaParam =
        #{
            <<"stable">> => STable,
            <<"fields">> => FilterThingInfo,
            <<"tags">> => Tags
        },
    create_schema(CreateSchemaParam).


add_columns(Table, Columns) ->
    lists:foreach(
        fun(Column) ->
            case add_column(Table, Column) of
                {ok, _, _} ->
                    ok;
                {error, Reason} ->
                    logger:error("add column ~p in table ~p failed ~p",
                        [Column, Table, Reason])
            end
        end, Columns).

add_column(Table, #{<<"name">> := Name, <<"type">> := Type}) ->
    FieldType = alinkiot_tdengine_common:transform_field_type(Type),
    Sql = <<"alter table ", Table/binary, " add column ", Name/binary, " ", FieldType/binary>>,
    request(Sql).


del_columns(Table, Columns) ->
    lists:foreach(
        fun(Column) ->
            case del_column(Table, Column) of
                {ok, _, _} ->
                    ok;
                {error, Reason} ->
                    logger:error("delete column ~p in table ~p failed ~p",
                        [Column, Table, Reason])
            end
    end, Columns).

del_column(Table, Column) ->
    Sql = <<"alter table ", Table/binary, " drop column ", Column/binary>>,
    request(Sql).





%% 插入
insert_object(TableName, #{<<"values">> := Values0} = Object) ->
    Values = format_batch(Object#{ <<"tableName">> => TableName, <<"values">> => [Values0]}),
    Sql = <<"INSERT INTO ", Values/binary, ";">>,
    request(Sql).

%% 查询，
query_history(_OperationID, Args, _Context, Req) ->
    case do_query_history(Args) of
        {ok, Count, Rows} ->
            CommonSuccessRes = alinkdata_ajax_result:success_result(),
            Res = maps:merge(#{total => Count, rows => Rows}, CommonSuccessRes),
            alinkdata_common_service:response(Res, Req);
        {ok, Rows} ->
            alinkdata_common_service:response(alinkdata_ajax_result:success_result(Rows), Req);
        {error, Reason} ->
            Msg = list_to_binary(io_lib:format("~p", [Reason])),
            alinkdata_common_service:response(alinkdata_ajax_result:error_result(Msg), Req)
    end.

do_query_history(#{<<"addr">> := Addr} = Args) ->
    Sql = <<"select thing from sys_product a, sys_device b where a.id = b.product and b.addr = '", Addr/binary, "'">>,
    case alinkdata:query_mysql_format_map(default, Sql) of
        {ok, [#{<<"thing">> := Thing}]} when Thing =/= <<>> ->
            ThingInfo = jiffy:decode(Thing, [return_maps]),
            ThingFields = lists:map(fun(#{<<"name">> := F}) -> F end, ThingInfo),
            Where =
                maps:fold(
                    fun(K, V, Acc) ->
                        LegalFields = [<<"time">>, <<"time[begin]">>, <<"time[end]">>|ThingFields],
                        case lists:member(K, LegalFields) of
                            true ->
                                Acc#{K => V};
                            _ ->
                                Acc
                        end
                end, #{}, Args),
            query_alink(Args#{<<"fields">> => ThingInfo, <<"where">> => Where});
        {ok, _} ->
            {error, <<"物模型出错"/utf8>>};
        {error, Reason} ->
            {error, Reason}
    end.

query_alink(Param) ->
    Table = parse_table(Param),
    Interval = parse_interval(Param),
    FieldsBin = to_fields_bin(Interval, maps:get(<<"fields">>, Param, [])),
    OrderBy = parse_order_by(Param),
    ParseWhere = parse_where(Param),
    Sql =
        case Interval of
            <<>> ->
                <<"select ", FieldsBin/binary, " from ", Table/binary,
                    " where 1 = 1 ", ParseWhere/binary, OrderBy/binary>>;
            _ ->
                <<"select ", FieldsBin/binary, " from ", Table/binary,
                    " where 1 = 1 ", ParseWhere/binary, Interval/binary, OrderBy/binary>>
        end,
    case parse_page(Param) of
        <<>> ->
            case request(Sql) of
                {ok, _, Rows} ->
                    {ok, Rows};
                {error, Reason} ->
                    {error, Reason}
            end;
        Limit ->
            case request(<<"select count(1) from (", Sql/binary, ")">>) of
                {ok, _, [#{<<"count(1)">> := Count}]} ->
                    case request(<<Sql/binary, Limit/binary>>) of
                        {ok, _, Rows} ->
                            {ok, Count, Rows};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end
    end.


parse_table(#{<<"addr">> := Addr}) ->
    AddrB = alinkutil_type:to_binary(Addr),
    <<"device_", AddrB/binary>>;
parse_table(#{<<"productId">> := ProductId}) ->
    ProductIdB = alinkutil_type:to_binary(ProductId),
    <<"alinkiot_", ProductIdB/binary>>.

parse_page(#{<<"pageSize">> := RPageSize, <<"pageNum">> := RPageNum}) ->
    PageSize = alinkutil_type:to_integer(RPageSize),
    PageNum = alinkutil_type:to_integer(RPageNum),
    Offset = PageSize * (PageNum - 1),
    PageSizeB = alinkutil_type:to_binary(PageSize),
    OffsetB = alinkutil_type:to_integer(Offset),
    <<" LIMIT ", OffsetB/binary, ",", PageSizeB/binary>>;
parse_page(_Param) ->
    <<>>.

parse_interval(#{<<"interval">> := Interval}) ->
    IntervalB = alinkutil_type:to_binary(Interval),
    <<" interval (", IntervalB/binary, ") ">>;
parse_interval(_) ->
    <<>>.


parse_order_by(#{<<"orderBy[desc]">> := Field}) ->
    <<" order by ", Field/binary, " desc">>;
parse_order_by(#{<<"orderBy[asc]">> := Field}) ->
    <<" order by ", Field/binary, " asc">>;
parse_order_by(_) ->
    <<>>.

parse_where(#{<<"where">> := Where}) ->
    maps:fold(
        fun(<<"time[begin]">>, V, Acc) ->
            VB = alinkiot_tdengine_common:to_sql_bin(V),
            <<Acc, " and time >= ", VB/binary>>;
           (<<"time[end]">>, V, Acc) ->
            VB = alinkiot_tdengine_common:to_sql_bin(V),
            <<Acc, " and time < ", VB/binary>>;
            (K, V, Acc) ->
            KB = alinkutil_type:to_binary(K),
            VB = alinkiot_tdengine_common:to_sql_bin(V),
            <<Acc, " and ", KB/binary, " = ", VB/binary>>
    end, <<>>, Where).


%% 下面的代码有点乱七八糟，找机会整理 TODO



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
    Host = application:get_env(alinkiot_tdengine, host, "127.0.0.1"),
    Port = application:get_env(alinkiot_tdengine, port, 6041),
    Username = application:get_env(alinkiot_tdengine, username, "root"),
    Password = application:get_env(alinkiot_tdengine, password, "taosdata"),
    Database = application:get_env(alinkiot_tdengine, database, ""),
    case alinkiot_tdengine_rest:simple_query(Host, Port, Username, Password, Database, Sql) of
        {ok, Row, Result} ->
            {ok, Row, format_result(Result)};
        {error, Reason} ->
            logger:error("Execute Fail ~p ~p ~p ~p", [Host, Port, Sql, Reason]),
            {error, Reason}
    end.



format_result(#{<<"count(*)">> := Count} = R) -> R#{<<"count">> => Count};
format_result(R) -> R.



%%%===================================================================
%%% Internal functions
%%%===================================================================
create_subtable_fields_bin(Fields) ->
    lists:foldl(
        fun(#{<<"name">> := K, <<"value">> := V}, {Acc0, Acc1}) ->
            KB = alinkutil_type:to_binary(K),
            VB = alinkiot_tdengine_common:to_sql_bin(V),
            case Acc0 of
                <<>> ->
                    {KB, VB};
                _ ->
                    {<<Acc0/binary, ",", KB/binary>>, <<Acc1/binary, ",", VB/binary>>}
            end
        end, {<<>>, <<>>}, Fields).

create_table_fields_bin(Fields) ->
    lists:foldl(
        fun(#{<<"name">> := Name, <<"type">> := Type}, Acc) ->
            RealType = alinkiot_tdengine_common:transform_field_type(Type),
            <<Acc/binary, ",", Name/binary, " ", RealType/binary>>
        end, <<>>, Fields).


create_table_tags_bin(Tags) ->
    lists:foldl(
        fun(#{<<"name">> := Name, <<"type">> := Type}, Acc) ->
            RealType = alinkiot_tdengine_common:transform_field_type(Type),
            case Acc of
                <<>> ->
                    <<Name/binary, " ", RealType/binary>>;
                _ ->
                    <<Acc/binary, ",", Name/binary, " ", RealType/binary>>
            end
    end, <<>>, Tags).

to_fields_bin(<<>>, []) ->
    <<"*">>;
to_fields_bin(<<>>, Fields) ->
    Fields1 = lists:filter(fun(#{<<"name">> := F}) -> F =/= <<"time">> end, Fields),
    lists:foldl(
        fun(F, Acc) ->
            <<Acc/binary, ",", F/binary>>
    end, <<"time">>, Fields1);
to_fields_bin(_, Fields) ->
    Fields1 = lists:filter(fun(#{<<"name">> := F}) -> F =/= <<"time">> end, Fields),
    lists:foldl(
        fun(#{<<"name">> := F,
              <<"type">> := Type}, Acc) when Type =:= <<"int">>
                                        orelse Type =:= <<"float">> ->
            <<Acc/binary, ", avg(", F/binary, ") as ", F/binary>>
        end, <<"_wstart as time">>, Fields1).