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
    case alinkiot_tdengine:request(<<"describe ", STable/binary>>) of
        {ok, _, TableInfo} ->
            ok;
        {error, Reason} ->
            logger:error("repaire failed ~p", [Reason])
    end.