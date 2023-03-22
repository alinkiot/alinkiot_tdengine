%%%-------------------------------------------------------------------
%%% @author yqfclid
%%% @copyright (C) 2023, yuqinfeng17@gmail.com
%%% @doc
%%%
%%% @end
%%% Created : 22. 3月 2023 上午1:19
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_sync).
-author("yqfclid").

%% API
-export([
    sync/0,
    sync/1
]).

%%%===================================================================
%%% API
%%%===================================================================
sync() ->
    case alinkdata_dao:query_no_count(#{}) of
        {ok, Products} ->
            lists:foreach(
                fun(#{<<"id">> := ProductId, <<"thing">> := Thing}) when Thing =/= <<>> ->
                    repaire(ProductId, jiffy:decode(Thing, [return_maps]));
                   (_) ->
                    ok
            end, Products);
        {error, Reason} ->
            logger:error("sync product info failed:~p", [Reason])
    end.

sync(ProductId) ->
    case alinkdata_dao:query_no_count(#{<<"id">> => ProductId}) of
        {ok, [#{<<"thing">> := Thing}]} when Thing =/= <<>> ->
            repaire(ProductId, Thing);
        {ok, _} ->
            ok;
        {error, Reason} ->
            logger:error("sync product info failed:~p", [Reason])
    end.
%%%===================================================================
%%% Internal functions
%%%===================================================================
repaire(ProductId, ThingInfo) ->
    ProductIdB = alinkutil_type:to_binary(ProductId),
    STable = <<"alinkiot_", ProductIdB/binary>>,
    case get_stable_schema(STable) of
        {ok, Schema} ->
            {AddColumns, DelColumns} = diff_schema_and_thing(Schema, ThingInfo),
            alinkiot_tdengine:del_columns(STable, DelColumns),
            alinkiot_tdengine:add_columns(STable, AddColumns);
        {error, not_found} ->
            alinkiot_tdengine:create_alink_schema(ProductId, ThingInfo);
        {error, Reason} ->
            logger:error("repaire failed ~p", [Reason])
    end.



get_stable_schema(STable) ->
    case alinkiot_tdengine:request(<<"show stables">>) of
        {ok, _, ExistsSTables} ->
            case lists:member(STable, maps:values(ExistsSTables)) of
                true ->
                    case alinkiot_tdengine:request(<<"describe ", STable/binary>>) of
                        {ok, _, Schema} ->
                            {ok, Schema};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                false ->
                    {error, not_found}
            end;
        {error, Reason} ->
            {error, Reason}
    end.



diff_schema_and_thing(Schema, ThingInfo) ->
    AddColmns =
        lists:foldl(
            fun(#{<<"name">> := Name, <<"type">> := Type}, Acc) when Name =/= <<"time">> ->
                IsExistInSchema =
                    lists:any(
                        fun(#{<<"field">> := Field, <<"type">> := FieldType}) when Field =:= Name->
                            case alinkiot_tdengine_common:transform_field_type(Type) of
                                FieldType ->
                                    true;
                                _ ->
                                    false
                            end;
                           (_) ->
                               false
                    end, Schema),
                case IsExistInSchema of
                    true ->
                        Acc;
                    false ->
                        [#{<<"name">> => Name, <<"type">> => Type}|Acc]
                end;
               (_, Acc) ->
                   Acc
        end, [], ThingInfo),
    DelColumns =
        lists:foldl(
            fun(#{<<"field">> := Field, <<"type">> := FieldType}, Acc) when Field =/= <<"time">> ->
                IsExistInThing =
                    lists:any(
                        fun(#{<<"name">> := Name, <<"type">> := Type}) when Name =:= Field ->
                            case alinkiot_tdengine_common:transform_field_type(Type) of
                                FieldType ->
                                    true;
                                _ ->
                                    false
                            end;
                            (_) ->
                                false
                        end, ThingInfo),
                case IsExistInThing of
                    true ->
                        Acc;
                    false ->
                        [Field|Acc]
                end;
                (_, Acc) ->
                    Acc
            end, [], Schema),
    {AddColmns, DelColumns}.