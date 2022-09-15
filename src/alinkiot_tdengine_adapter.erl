%%%-------------------------------------------------------------------
%%% @author kenneth
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%% 消息适配器
%%% @end
%%% Created : 28. 四月 2020 17:11
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_adapter).
-include("alinkiot_tdengine.hrl").
-author("kenneth").

%% API
-export([save/1, save/2, do_save/2, test/1]).
-export([init/1, get_channel/2, scan_subdev/3]).
-export([test/2]).

get_channel(ProductId, App) ->
    Role = <<"role:", App/binary>>,
    Result =
        case alinkiot_parse:query_object(<<"Channel">>, #{<<"where">> => #{<<"cType">> => <<"TD">>}, <<"limit">> => 10}) of
            {ok, #{<<"results">> := []}} -> pass;
            {ok, #{<<"results">> := [#{<<"objectId">> := ChannelId, <<"ACL">> := #{Role := _}}]}} ->
                logger:info("ChannelId ~p ", [ChannelId]),
                Where = #{<<"$relatedTo">> => #{
                    <<"object">> => #{
                        <<"__type">> => <<"Pointer">>,
                        <<"className">> => <<"Channel">>,
                        <<"objectId">> => ChannelId},
                    <<"key">> => <<"product">>
                }},
                Query = #{<<"limit">> => 1, <<"where">> => Where, <<"order">> => <<"-updatedAt">>},
                case alinkiot_parse:query_object(<<"Product">>, Query) of
                    {ok, #{<<"results">> := []}} -> #{};
                    {ok, #{<<"results">> := Products}} ->
                        {lists:any(fun(E) ->
                            case E of
                                #{<<"objectId">> := ProductId} ->
                                    true;
                                _ -> false
                            end
                                   end, Products), ChannelId};
                    _ -> {false, <<"">>}
                end;
            _ -> {false, <<"">>}
        end,
    case Result of
        {true, Chl} -> Chl;
        _ -> <<"">>
    end.


scan_subdev(_App, ProductId, DtuAddr) ->
    Query = #{
        <<"keys">> => [<<"route">>, <<"devaddr">>, <<"product">>],
        <<"where">> => #{
            <<"route.", DtuAddr/binary>> => #{
                <<"$regex">> => <<".+">>
            }
        },
        <<"order">> => <<"devaddr">>,
        <<"limit">> => 256,
        <<"include">> => <<"product">>
    },
    Devices = case alinkiot_parse:query_object(<<"Device">>, Query) of
                  {ok, #{<<"results">> := []}} -> [];
                  {ok, #{<<"results">> := List}} -> List;
                  _ -> []
              end,
    lists:map(fun(X) ->
        #{
            <<"objectId">> :=  ObjectId,
            <<"product">> := #{<<"objectId">> := SubProductId},
            <<"route">> := #{DtuAddr := _Pn}
        } = X,
        logger:info("ObjectId ~p ", [ObjectId]),
        alinkiot_parse:update_object(<<"Device">>, ObjectId, #{
            <<"isEnable">> => true,
            <<"status">> => <<"ONLINE">>
        }),
        %%初始化td库
        alinkiot_tdengine_adapter:init(SubProductId),
        alinkiot_product:load(ProductId)
              end, Devices),
    case alinkiot_parse:query_object(<<"Device">>, #{<<"where">> => #{<<"devaddr">> => DtuAddr}, <<"limit">> => 1}) of
        {ok, #{<<"results">> := []}} -> [];
        {ok, #{<<"results">> := [#{<<"objectId">> :=  DTUId}]}} ->
            alinkiot_parse:update_object(<<"Device">>, DTUId, #{
                <<"isEnable">> => true,
                <<"status">> => <<"ONLINE">>
            });
        _ -> []
    end.

%%初始化td库
init(_ProdcutId) ->
    ok.




save(Product, Msg) when is_map(Msg) ->
    do_channel(Product,
        fun(Channel) ->
            do_save(Channel, Msg)
        end).

save(#{<<"product">> := Product} = Msg) ->
    case format(Msg) of
        ignore ->
            ignore;
        {ok, Batch} ->
            save(Product, Batch);
        {error, Reason} ->
            logger:warning("~p format error ~p!", [Msg, Reason]),
            {error, Reason}
    end.

do_save(Channel, Msg) ->
    alinkiot_channelx:do_message(?TYPE, Channel, {data, Msg, #{}}, 30000).

do_channel(Product, Fun) ->
    case alinkiot_data:lookup({Product, <<"TD">>}) of
        {ok, Channel} ->
            Fun(Channel);
        {error, not_find} ->
            logger:warning("~s not find tdengine channel!", [Product]),
            {error, not_find_tdengine}
    end.


format(#{
    <<"devaddr">> := DevAddr,
    <<"dtuaddr">> := DtuAddr,
    <<"product">> := Product,
    <<"thing">> := Things
}) ->
    Data = format_thing(Things),
    case maps:size(Data) == 0 of
        true ->
            ignore;
        false ->
            {ok, Data#{
                <<"dtuaddr">> => DtuAddr,
                <<"product">> => Product,
                <<"addr">> => DevAddr
            }}
    end;
format(_) ->
    {error, not_match}.



format_thing(Things) -> format_thing(Things, #{}).
format_thing([], Acc) -> Acc;
format_thing([#{<<"value">> := Value, <<"identifier">> := Id} | Other], Acc) ->
    format_thing(Other, Acc#{Id => Value}).


test(Count) ->
    test(<<"yDjxYIhX4K">>, Count).

test(Product, Count) ->
    test(Product, 0, Count).

test(Product, I, Count) when I < Count ->
    Addr = list_to_binary(io_lib:format("JDYTMEP~6.10.0B,", [I])),
    Msg = #{
        <<"app">> => <<"fbox">>, <<"devaddr">> => Addr,
        <<"dtuaddr">> => <<"1021702257">>,
        <<"product">> => Product,
        <<"thing">> =>
        [#{<<"accessMode">> => <<"r">>,
            <<"dataType">> =>
            #{<<"specs">> =>
            #{<<"max">> => 1000, <<"min">> => 0, <<"step">> => 0.01,
                <<"unit">> => <<"%RH">>},
                <<"type">> => <<"float">>},
            <<"identifier">> => <<"humidity">>,
            <<"name">> => <<230, 185, 191, 229, 186, 166>>,
            <<"required">> => true, <<"time">> => 1587983022,
            <<"value">> => 23.0},
            #{<<"accessMode">> => <<"r">>,
                <<"dataType">> =>
                #{<<"specs">> =>
                #{<<"max">> => 100, <<"min">> => 1, <<"step">> => 0.01,
                    <<"unit">> => <<"°C"/utf8>>},
                    <<"type">> => <<"float">>},
                <<"identifier">> => <<"temp">>,
                <<"name">> => <<230, 184, 169, 229, 186, 166>>,
                <<"required">> => true, <<"time">> => 1587983022,
                <<"value">> => 10.0}]},
    alinkiot_tdengine_adapter:save(Msg),
    test(Product, I + 1, Count);
test(_, _, _) ->
    ok.


