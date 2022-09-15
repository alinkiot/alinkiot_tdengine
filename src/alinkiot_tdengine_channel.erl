%%%-------------------------------------------------------------------
%%% @author kenneth
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 23. 四月 2020 13:34
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_channel).
-author("kenneth").
-define(CACHE(Channel), binary_to_atom(<<?TYPE/binary, Channel/binary>>, utf8)).
-include("alinkiot_tdengine.hrl").
-author("kenneth").
-record(state, {id, env, product, status}).
%% API
-export([start/2, transaction/2, run_sql/3, handle_save/1, save_to_cache/2]).
-export([init/3, handle_event/3, handle_message/2, stop/3]).
-export([test/1]).

%% 注册通道类型
-channel(?TYPE).
-channel_type(#{
    type => 2,
    title => #{
        zh => <<"TD存储通道"/utf8>>
    },
    description => #{
        zh => <<"TD存储通道"/utf8>>
    }
}).
%% 注册通道参数
-params(#{
    <<"ip">> => #{
        order => 1,
        type => string,
        required => true,
        default => <<"127.0.0.1">>,
        title => #{
            zh => <<"服务器地址"/utf8>>
        },
        description => #{
            zh => <<"服务器地址"/utf8>>
        }
    },
    <<"port">> => #{
        order => 2,
        type => integer,
        required => true,
        default => 6020,
        title => #{
            zh => <<"端口"/utf8>>
        },
        description => #{
            zh => <<"端口"/utf8>>
        }
    },
    <<"database">> => #{
        order => 3,
        type => string,
        required => true,
        default => <<"alinkiot">>,
        title => #{
            zh => <<"数据库名称"/utf8>>
        },
        description => #{
            zh => <<"数据库名称"/utf8>>
        }
    },
    <<"keep">> => #{
        order => 3,
        type => integer,
        required => true,
        default => 365,
        title => #{
            zh => <<"数据保留时间"/utf8>>
        },
        description => #{
            zh => <<"数据保留时间"/utf8>>
        }
    },
    <<"username">> => #{
        order => 4,
        type => string,
        required => true,
        default => <<"root">>,
        title => #{
            zh => <<"用户名"/utf8>>
        },
        description => #{
            zh => <<"用户名"/utf8>>
        }
    },
    <<"password">> => #{
        order => 5,
        type => string,
        required => true,
        default => <<"taosdata">>,
        title => #{
            zh => <<"密码"/utf8>>
        },
        description => #{
            zh => <<"密码"/utf8>>
        }
    },
    <<"driver">> => #{
        order => 6,
        type => string,
        required => true,
        default => <<"HTTP">>,
        title => #{
            zh => <<"连接方式"/utf8>>
        },
        description => #{
            zh => <<"连接方式包括HTTP请求或JDBC"/utf8>>
        }
    },
    <<"id">> => #{
        order => 8,
        type => string,
        required => false,
        default => <<>>,
        title => #{
            zh => <<"通道ID"/utf8>>
        },
        description => #{
            zh => <<"指定通道ID"/utf8>>
        }
    }
}).

transaction(Channel, Fun) ->
    case alinkiot_channelx:call(?TYPE, Channel, config) of
        {ok, Context} ->
            Fun(Context);
        {error, Reason} ->
            {error, Reason}
    end.

%% Action 用来区分数据库操作语句类型(DQL、DML、DDL、DCL)
run_sql(#{<<"driver">> := <<"HTTP">>, <<"url">> := Url, <<"username">> := UserName, <<"password">> := Password}, _Action, Sql) ->
    case alinkiot_tdrestful:request(Url, UserName, Password, Sql) of
        {ok, Result} ->
            %logger:debug("Execute ~p (~p) ~p", [Url, Sql, Result]),
            {ok, Result};
        {error, Reason} ->
            logger:error("Execute Fail ~p (~p) ~p", [Url, Sql, Reason]),
            {error, Reason}
    end;
run_sql(#{<<"driver">> := <<"JDBC">>}, Action, Sql) when Action == execute_update; Action == execute_query ->
    %logger:debug("Execute ~p (~p) ~p", [Url, byte_size(Sql), Sql]),
    apply(ejdbc, Action, [<<"com.taosdata.jdbc.TSDBDriver">>, Sql]).


%% 先缓存定时存库
save_to_cache(Channel, Requests) when is_list(Requests) ->
    ETS = ?CACHE(Channel),
    Key = erlang:system_time(millisecond),
    NewRequest =
        case alinkiot_dcache:lookup(ETS, Key) of
            {ok, Acc} ->
                lists:foldl(fun(Request, Acc1) -> [Request | Acc1] end, Acc, Requests);
            {error, not_find} ->
                Requests
        end,
    alinkiot_dcache:insert(?CACHE(Channel), {Key, NewRequest}),
    case check_cache(Channel) of
        true ->
            alinkiot_channelx:do_event(?TYPE, Channel, full, self()),
            ok;
        false ->
            ok
    end;
save_to_cache(Channel, Request) when is_map(Request) ->
    save_to_cache(Channel, [Request]).


start(ChannelId, #{
    <<"ip">> := Ip,
    <<"port">> := Port,
    <<"database">> := DB,
    <<"driver">> := Driver0,
    <<"username">> := UserName,
    <<"password">> := Password
} = Cfg) ->
    alinkiot_tdrestful:start(),
    {Driver, Url} =
        case list_to_binary(string:uppercase(binary_to_list(Driver0))) of
            <<"JDBC">> ->
                {<<"JDBC">>, list_to_binary(lists:concat(["jdbc:TAOS://", binary_to_list(Ip), ":", Port, "/", binary_to_list(DB)]))};
            _ ->
                {<<"HTTP">>, list_to_binary(lists:concat(["http://", binary_to_list(Ip), ":", Port, "/rest/sql"]))}
        end,
    Keep = min(maps:get(<<"keep">>, Cfg, 365 * 5), 365 * 5),
    Args1 = #{
        <<"driver">> => Driver,
        <<"keep">> => Keep,
        <<"url">> => Url,
        <<"database">> => DB,
        <<"username">> => UserName,
        <<"password">> => Password
    },
    case maps:get(<<"id">>, Cfg, <<>>) of
        <<>> ->
            alinkiot_channelx:add(?TYPE, ChannelId, ?MODULE, Args1);
        ServerName ->
            alinkiot_channelx:add2(ServerName, ?TYPE, ChannelId, ?MODULE, Args1)
    end.


%% 通道初始化
init(?TYPE, ChannelId, Config) ->
    case alinkiot_bridge:get_products(ChannelId) of
        {ok, _, ProductIds} ->
            do_check(ChannelId, ProductIds, Config),
            Opts = [?CACHE(ChannelId), #{
                auto_save => application:get_env(alinkiot_tdengine, cache_auto_save, 30000),
                size => application:get_env(alinkiot_tdengine, cache_max_size, 50000),
                memory => application:get_env(alinkiot_tdengine, cache_max_memory, 102400),
                max_time =>  application:get_env(alinkiot_tdengine, cache_max_time, 30),
                handle => {?MODULE, handle_save, [ChannelId]}
            }],
            State = #state{
                id = ChannelId,
                env = Config,
                product = ProductIds
            },
            Specs = [
                {alinkiot_dcache, {alinkiot_dcache, start_link, Opts}, permanent, 5000, worker, [alinkiot_dcache]}
            ],
            {ok, State, Specs};
        {error, not_find} ->
            {stop, not_find_product}
    end.

%% 通道消息处理,注意：进程池调用
handle_event(full, _From, #state{id = Channel}) ->
    alinkiot_dcache:save_to_disk(?CACHE(Channel)),
    ok;

handle_event(EventType, Event, _State) ->
    logger:info("channel ~p, ~p", [EventType, Event]),
    ok.

%% 规则引擎导入
handle_message({rule, Msg, Context}, State) ->
    handle_message({data, Msg, Context}, State);

%% 进程消息
handle_message({data, #{<<"type">> := <<"report">>} = Data, Context}, State) ->
    case catch do_save([Data, Context], State) of
        {Err, Reason} when Err == error; Err == 'EXIT' ->
            logger:error("Save to Tdengine error, ~p, ~p", [Data, Reason]),
            ok;
        {ok, NewState} ->
            {ok, NewState}
    end;

handle_message(config, #state{env = Config} = State) ->
    {reply, {ok, Config}, State};
handle_message(Message, #state{id = ChannelId, product = ProductId} = _State) ->
    logger:info("Channel ~p, Product ~p, handle_message ~p", [ChannelId, ProductId, Message]),
    ok.

handle_save(Channel) ->
    %{_Time, _} = timer:tc(fun() -> save_cache(Channel) end),
    %logger:info("save:~p~n", [Time / 1000000]),
    save_cache(Channel),
    ok.

stop(ChannelType, ChannelId, _) ->
    alinkiot_product:del_handler(ChannelId),
    logger:info("channel stop ~p,~p", [ChannelType, ChannelId]),
    ok.

%% 存储 对于一个通道对应多个产品时，依次调用所有产品解码器 handle_save
do_save([#{ <<"productId">> := ProductId} = Data, _Context], #state{id = ChannelId, env = #{<<"database">> := DB}} = State) ->
    case alinkiot_bridge:get_product_info(ProductId) of
        {error, Reason} ->
            logger:error("Save to tdengine error, ~p, ~p", [Data, Reason]);
        {ok, #{<<"thing">> := Properties}} ->
            Object = format_data(ChannelId, ProductId, Properties, Data),
            save_to_cache(ChannelId, Object#{
                <<"db">> => DB
            })
    end,
    {ok, State}.

format_data(ChannelId, ProductId, Properties, #{<<"addr">> := Addr} = Data) ->
    Values = check_fields(Data, Properties),
    Fields = maps:keys(Values),
    #{
        <<"tableName">> => ?Table(Addr),
        <<"using">> => ?Table(ProductId),
        <<"tags">> => [ChannelId],
        <<"fields">> => [<<"createdAt">> | Fields],
        <<"values">> => [
            [now | [maps:get(Key, Values) || Key <- Fields]]
        ]
    }.


save_cache(Channel) ->
    Max = 50,
    Fun =
        fun({Idx, Requests}, Acc) ->
            true = alinkiot_dcache:delete(?CACHE(Channel), Idx),
            save_cache(Channel, Max, Requests, Acc)
        end,
    save_to_tdengine(Channel, alinkiot_dcache:search(?CACHE(Channel), Fun)).



save_cache(Channel, Max, [Request | Requests], Acc) when length(Acc) < Max - 1 ->
    save_cache(Channel, Max, Requests, [Request | Acc]);
save_cache(Channel, Max, [Request | Requests], Acc) when length(Acc) == Max - 1 ->
    ok = save_to_tdengine(Channel, [Request | Acc]),
    save_cache(Channel, Max, Requests, []);
save_cache(_, _, [], Acc) ->
    {true, Acc}.


save_to_tdengine(_, []) -> ok;
save_to_tdengine(Channel, Requests) ->
    case alinkiot_tdengine:batch(Channel, Requests) of
        {ok, _Results} ->
            %logger:info("Batch ~p-> ~p~n", [length(Requests), Results]),
            ok;
        {error, Reason} when Reason == timeout; Reason == disconnect ->
            save_to_cache(Channel, Requests),
            ok;
        {error, Reason} ->
            logger:error("save cache,~p,~p~n", [Requests, Reason]),
            %save_to_cache(Channel, Requests),
            ok
    end.


check_cache(Channel) ->
    Info = alinkiot_dcache:info(?CACHE(Channel)),
    {size, Size} = lists:keyfind(size, 1, Info),
    case Size =< 100 of
        true ->
            true;
        false ->
            {memory, Memory} = lists:keyfind(memory, 1, Info),
            MaxSize = application:get_env(alinkiot_tdengine, cache_max_size, 1000),
            MaxMemory = application:get_env(alinkiot_tdengine, cache_max_memory, 102400),
            Size >= MaxSize orelse Memory >= MaxMemory
    end.


do_check(ChannelId, ProductIds, Config) ->
    spawn(
        fun() ->
            timer:sleep(500),
            check_init(ChannelId, ProductIds, Config)
        end).

check_init(ChannelId, ProductIds, Config) ->
    check_database(ChannelId, ProductIds, Config),
    ok.

check_database(ChannelId, ProductIds, #{<<"database">> := DataBase, <<"keep">> := Keep} = Config) ->
    case alinkiot_tdengine:create_database(ChannelId, DataBase, Keep) of
        {error, <<"channel not find">>} ->
            ok;
        {error, #{<<"code">> := 10, <<"desc">> := <<"authentication failure">>}} ->
            alinkiot_bridge:send_log(ChannelId, "Check database Error, ChannelId:~p, ProductIds:~p, Reason:authentication failure", [ChannelId, ProductIds]),
            timer:sleep(5000),
            check_database(ChannelId, ProductIds, Config);
        {error, Reason} ->
            logger:error("Check database Error, ChannelId:~p, ProductIds:~p, Reason:~p", [ChannelId, ProductIds, Reason]),
            alinkiot_bridge:send_log(ChannelId, "Check database Error, ChannelId:~p, ProductIds:~p, Reason:~p", [ChannelId, ProductIds, Reason]),
            timer:sleep(5000),
            check_database(ChannelId, ProductIds, Config);
        {ok, #{<<"affected_rows">> := Rows}} when Rows > 0 ->
            logger:info("Check database ChannelId:~p, ProductIds:~p, Config:~p", [ChannelId, ProductIds, Config]),
            create_table(ChannelId, ProductIds, Config)
    end.

create_table(_, [], _) ->
    ok;
create_table(ChannelId, [ProductId | ProductIds], Config) ->
    case alinkiot_bridge:get_product_info(ProductId) of
        {ok, Product} ->
            case get_schema(ChannelId, Product) of
                ignore ->
                    ok;
                Schema ->
                    alinkiot_product:add_handler(ProductId, ChannelId, 'message.publish', {channel, ?TYPE}),
                    TableName = ?Table(ProductId),
                    case alinkiot_tdengine:create_schemas(ChannelId, Schema#{
                        <<"tableName">> => TableName
                    }) of
                        {error, Reason} ->
                            logger:error("Create Table[~s] Fail, Schema:~p, Reason:~p", [TableName, Schema, Reason]);
                        {ok, #{<<"affected_rows">> := _}} ->
                            logger:info("Create Table[~s] Succ, Schema:~p", [TableName, Schema])
                    end
            end;
        {error, Reason} ->
            logger:error("Create Table Error, ~p", [Reason])
    end,
    create_table(ChannelId, ProductIds, Config).

get_schema(ChannelId, #{<<"thing">> := Thing}) ->
    Properties = maps:get(<<"properties">>, Thing, []),
    case lists:flatten([get_field(Property) || Property <- Properties]) of
        [] ->
            ignore;
        Columns ->
            Size = integer_to_binary(byte_size(ChannelId)),
            #{
                <<"fields">> => Columns,
                <<"tags">> => [
                    {
                        <<"channel">>, #{<<"type">> => <<"NCHAR(", Size/binary, ")">>}
                    }
                ]
            }
    end.

get_field(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"int">>}}) ->
    {Field, #{<<"type">> => <<"INT">>}};
get_field(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"float">>}}) ->
    {Field, #{<<"type">> => <<"FLOAT">>}};
get_field(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"date">>}}) ->
    {Field, #{<<"type">> => <<"TIMESTAMP">>}};
get_field(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"bool">>}}) ->
    {Field, #{<<"type">> => <<"BOOL">>}};
get_field(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"double">>}}) ->
    {Field, #{<<"type">> => <<"DOUBLE">>}};
get_field(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"string">>} = Spec}) ->
    Size = integer_to_binary(min(maps:get(<<"size">>, Spec, 10), 40)),
    {Field, #{<<"type">> => <<"NCHAR(", Size/binary, ")">>}};
get_field(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"enum">>, <<"specs">> := Specs}}) ->
    Size = integer_to_binary(maps:size(Specs)),
    {Field, #{<<"type">> => <<"NCHAR(", Size/binary, ")">>}};
get_field(#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := <<"struct">>, <<"specs">> := SubFields}}) ->
    [get_field(SubField#{<<"identifier">> => ?Struct(Field, Field1)}) || #{<<"identifier">> := Field1} = SubField <- SubFields].


check_fields(Data, #{ <<"properties">> := Props }) -> check_fields(Data, Props);
check_fields(Data, Props) -> check_fields(Data, Props, #{}).
check_fields(Data, Props, Acc) when Data == []; Props == [] -> Acc;
check_fields(Data, [#{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := Type} = DataType} = Prop | Other], Acc) ->
    case check_field(Data, Prop) of
        undefined ->
            check_fields(Data, Other, Acc);
        Value ->
            case list_to_binary(string:to_upper(binary_to_list(Type))) of
                <<"STRUCT">> ->
                    #{<<"specs">> := SubFields} = DataType,
                    Acc2 = lists:foldl(
                        fun(#{<<"identifier">> := Field1} = SubField, Acc1) ->
                            case check_field(Value, SubField) of
                                undefined ->
                                    Acc1;
                                Value1 ->
                                    Acc1#{?Struct(Field, Field1) => Value1}
                            end
                        end, Acc, SubFields),
                    check_fields(Data, Other, Acc2);
                _ ->
                    check_fields(Data, Other, Acc#{Field => Value})
            end
    end.

check_field(Data, Props) when is_map(Data) ->
    check_field(maps:to_list(Data), Props);
check_field(Data, #{<<"identifier">> := Field, <<"dataType">> := #{<<"type">> := Type} = DataType}) ->
    case proplists:get_value(Field, Data) of
        undefined ->
            undefined;
        Value ->
            Type1 = list_to_binary(string:to_upper(binary_to_list(Type))),
            Is =
                case Type1 of
                    _ when Type1 == <<"INT">>; Type1 == <<"DATE">> ->
                        is_integer(Value);
                    _ when Type1 == <<"FLOAT">>; Type1 == <<"DOUBLE">> ->
                        is_float(Value);
                    <<"BOOL">> ->
                        is_boolean(Value);
                    <<"STRING">> ->
                        is_binary(Value);
                    <<"ENUM">> ->
                        #{<<"specs">> := Specs} = DataType,
                        lists:member(Value, maps:keys(Specs));
                    <<"STRUCT">> ->
                        is_map(Value) orelse is_list(Value)
                end,
            case Is of
                true ->
                    Value;
                false ->
                    throw({error, <<Field/binary, " is not ", Type/binary>>})
            end
    end.



test(Count) ->
    test(1, Count).

test(I, Max) when I =< Max ->
    Addr = list_to_binary(io_lib:format("~8.10.0B,", [I])),
    Msg = {rule, #{
        <<"addr">> => Addr,
        <<"te">> => 1,
        <<"te1">> => 2.2,
        <<"te2">> => 3.2,
        <<"te3">> => true,
        <<"te4">> => <<"1">>,
        <<"te5">> => <<"zww">>,
        <<"te6">> => 1587917728,
        <<"te7">> => #{
            <<"fasfd">> => 4
        }
    }, #{<<"channel">> => <<"aaaaaa">>}},
    alinkiot_channelx:do_message(?TYPE, <<"09oqrvmPjr">>, Msg, 30000),
    test(I + 1, Max);
test(_, _) -> ok.
