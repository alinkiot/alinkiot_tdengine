%%%-------------------------------------------------------------------
%%% @author yqfclid
%%% @copyright (C) 2022
%%% @doc
%%%
%%% @end
%%% Created : 20. 9月 2022 下午3:54
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_hook).
-author("yqfclid").

%% API
-export([
    load/0,
    unload/0,
    reload/0,
    on_message_publish/2
]).


-include_lib("emqx/include/emqx.hrl").
-include("alinkiot_tdengine.hrl").
%%%===================================================================
%%% API
%%%===================================================================
load() ->
    _ = emqx:hook('message.publish', fun ?MODULE:on_message_publish/2, [[]]),
    ok.

unload() ->
    emqx:unhook('message.publish', fun ?MODULE:on_message_publish/2),
    ok.

reload() ->
    unload(),
    reload().


on_message_publish(Msg, _Env) ->
    check_and_store(Msg),
    {ok, Msg}.
%%%===================================================================
%%% Application callbacks
%%%===================================================================
check_and_store(#message{topic = Topic}) ->
    case proplists:get_value() of

    end,
    ok.
