%%%-------------------------------------------------------------------
%%% @author alinkiot
%%% @copyright (C) 2019, alinkiot
%%% @doc
%%% API 处理模块 产生时间: Mon, 27 Apr 2020 12:54:08 +0800
%%% @end
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_handler).
-include("alinkiot_tdengine.hrl").
-ehttpd_rest(ehttpd).

%% API
-export([swagger_tdengine/0]).
-export([handle/4]).
-export([get_data/2]).

%% API描述
%% 支持二种方式导入
%% 示例:
%% 1. Metadata为map表示的JSON,
%%    ehttpd_server:bind(<<"/tdengine">>, ?MODULE, [], Metadata)
%% 2. 从模块的priv/swagger/下导入
%%    ehttpd_server:bind(<<"/swagger_tdengine.json">>, ?MODULE, [], priv)
swagger_tdengine() ->
    [
        ehttpd_server:bind(<<"/swagger_tdengine.json">>, ?MODULE, [], priv)
    ].


%%%===================================================================
%%% 请求处理
%%%  如果登录, Context 内有 <<"user">>, version
%%%===================================================================

-spec handle(OperationID :: atom(), Args :: map(), Context :: map(), Req :: ehttpd_req:req()) ->
    {Status :: ehttpd_req:http_status(), Body :: map()} |
    {Status :: ehttpd_req:http_status(), Headers :: map(), Body :: map()} |
    {Status :: ehttpd_req:http_status(), Headers :: map(), Body :: map(), Req :: ehttpd_req:req()}.

handle(OperationID, Args, Context, Req) ->
    Headers = #{},
    case catch do_request(OperationID, Args, Context, Req) of
        {ErrType, Reason} when ErrType == 'EXIT'; ErrType == error ->
            logger:info("do request: ~p, ~p, ~p~n", [OperationID, Args, Reason]),
            Err = case is_binary(Reason) of
                      true -> Reason;
                      false -> list_to_binary(io_lib:format("~p", [Reason]))
                  end,
            {500, Headers, #{<<"error">> => Err}};
        ok ->
            %logger:debug("do request: ~p, ~p ->ok ~n", [OperationID, Args]),
            {200, Headers, #{}, Req};
        {ok, Res} ->
            %logger:info("do request: ~p, ~p ->~p~n", [OperationID, Args, Res]),
            {200, Headers, Res, Req};
        {Status, Res} ->
            %logger:debug("do request: ~p, ~p ->~p~n", [OperationID, Args, Res]),
            {Status, Headers, Res, Req};
        {Status, NewHeaders, Res} ->
            %logger:debug("do request: ~p, ~p ->~p~n", [OperationID, Args, Res]),
            {Status, maps:merge(Headers, NewHeaders), Res, Req};
        {Status, NewHeaders, Res, NewReq} ->
            %logger:debug("do request: ~p, ~p ->~p~n", [OperationID, Args, Res]),
            {Status, maps:merge(Headers, NewHeaders), Res, NewReq}
    end.


%%%===================================================================
%%% 内部函数 Version:API版本
%%%===================================================================


%% TDengine 概要: 获取当前产品下的所有设备数据 描述:获取当前产品下的所有设备数据
%% OperationId:get_td_cid_pid
%% 请求:GET /iotapi/td/:ProductId/:channelId/:productId
%%do_request(get_product_cid_pid, #{
%%    <<"cid">> := ChannelId1,
%%    <<"pid">> := ProductId,
%%    <<"where">> := Where1,
%%    <<"keys">> := Keys
%%} = Args, #{ <<"sessionToken">> := SessionToken } = _Context, _Req) ->
%%    Fun =
%%        fun(ChannelId) ->
%%            TableName = ?Table(ProductId),
%%            Query = maps:without([<<"cid">>, <<"pid">>], Args),
%%            Where = format_where(Where1),
%%            case alinkiot_tdengine:query_object(ChannelId, TableName, Query#{
%%                <<"keys">> => format_keys(Keys),
%%                <<"where">> => Where
%%            }) of
%%                {ok, Data} ->
%%                    {ok, Data};
%%                {error, Reason} ->
%%                    {400, Reason}
%%            end
%%        end,
%%    case ChannelId1 == <<"default">> of
%%        false ->
%%            Fun(ChannelId1);
%%        true ->
%%            do_channel(ProductId, SessionToken, Fun)
%%    end;

%% TDengine 概要: 获取当前产品下的所有设备数据 描述:获取当前产品下的所有设备数据
%% OperationId:get_td_productid_channelid_addr_productid
%% 请求:GET /iotapi/td/:ProductId/:channelId/:addr/:productId
do_request(get_device_pid_addr, #{
    <<"pid">> := ProductId,
    <<"addr">> := Addr
%%    <<"where">> := Where1
}, #{<<"sessionToken">> := _SessionToken} = _Context, _Req) ->
    case get_data(ProductId, Addr) of
        {ok, Data} ->
            {ok, #{ results => Data }};
        {error, Reason} ->
            {400, Reason}
    end;


%%  服务器不支持的API接口
do_request(_OperationId, _Args, _Context, _Req) ->
    {error, <<"Not Allowed.">>}.


%%do_channel(ProductId, Session, Fun) ->
%%    Body = #{
%%        <<"keys">> => <<"objectId">>,
%%        <<"order">> => <<"-createdAt">>,
%%        <<"limit">> => 1,
%%        <<"where">> => #{
%%            <<"cType">> => ?TYPE,
%%            <<"isEnable">> => true,
%%            <<"product">> => #{
%%                <<"__type">> => <<"Pointer">>,
%%                <<"className">> => <<"Product">>,
%%                <<"objectId">> => ProductId
%%            }
%%        }
%%    },
%%    case alinkiot_parse:query_object(<<"Channel">>, Body, [{"X-Parse-Session-Token", Session}], [{from, rest}]) of
%%        {ok, #{<<"results">> := []}} ->
%%            {404, #{ code => 31, error => <<"not find channel">> }};
%%        {ok, #{<<"results">> := [#{<<"objectId">> := ChannelId}]}} ->
%%            Fun(ChannelId);
%%        {error, Reason} ->
%%            {error, Reason}
%%    end.

%%
%%format_keys(Keys) when is_binary(Keys), Keys =/= <<>> ->
%%    <<Keys/binary, ",tbname as addr">>;
%%format_keys(_) ->
%%    <<"*,tbname as addr">>.
%%
%%format_where(Where) when is_binary(Where), Where =/= <<>> ->
%%    jsx:decode(re:replace(Where, <<"addr">>, <<"tbname">>, [global, {return, binary}]), [ {labels, binary},return_maps]);
%%format_where(_) ->
%%    <<>>.



get_data(ProductId, DevId) ->
    case alinkcore_data:lookup(ProductId, DevId) of
        undefined ->
            {ok, []};
        Data ->
            case alinkiot_parse:get_object(<<"Product">>, ProductId) of
                {ok, #{<<"thing">> := Thing}} ->
                    Properties = maps:get(<<"properties">>, Thing, []),
                    NewData =
                        lists:foldl(
                            fun(#{<<"identifier">> := Id} = Prop, Acc) ->
                                case maps:get(Id, Data, undefined) of
                                    undefined -> Acc;
                                    #{ <<"value">> := Value, <<"ts">> := Time } ->
                                        [Prop#{value => Value, time => Time} | Acc]
                                end
                            end, [], Properties),
                    {ok, NewData};
                {error, _Reason} ->
                    {ok, []}
            end
    end.





%%format_data(#{<<"keys">> := <<"last_row(*)">>}, ProductId, #{<<"results">> := [Data]}) ->
%%    case alinkiot_bridge:get_product_info(ProductId) of
%%        {ok, #{<<"thing">> := Thing}} ->
%%            Properties = maps:get(<<"properties">>, Thing, []),
%%            NewData =
%%                lists:foldl(
%%                    fun(#{<<"identifier">> := Id} = Prop, Acc) ->
%%                        Time = to_unixtime(maps:get(<<"createdat">>, Data)),
%%                        case maps:get(list_to_binary(string:to_lower(binary_to_list(Id))), Data, no) of
%%                            no -> Acc;
%%                            Value -> [Prop#{value => Value, time => Time} | Acc]
%%                        end
%%                    end, [], Properties),
%%            {ok, #{ <<"results">> => NewData }};
%%        _ ->
%%            {ok, []}
%%    end;
%%format_data(_, _, Data) ->
%%    {ok, Data}.

%%to_unixtime(Time) ->
%%    Size = byte_size(Time) - 4,
%%    <<DateTime:Size/binary, _/binary>> = Time,
%%    alinkiot_datetime:to_unixtime(alinkiot_datetime:to_localtime(DateTime)).
