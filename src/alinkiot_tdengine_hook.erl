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
    case alinkiot_tdengine_writer:lookup_writer(Msg#message.from) of
        {ok, Writer} ->
            alinkiot_tdengine_writer:write(Writer, Msg);
        {error, not_found} ->
            ignore;
        {error, Reason} ->
            logger:error("message ~p found writer failed:~p", [Msg, Reason])
    end,
    {ok, Msg}.
%%%===================================================================
%%% Application callbacks
%%%===================================================================

