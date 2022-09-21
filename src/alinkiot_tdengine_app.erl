%%%-------------------------------------------------------------------
%% @end
%%%-------------------------------------------------------------------

-module(alinkiot_tdengine_app).
-include("alinkiot_tdengine.hrl").

-emqx_plugin(?MODULE).
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    {ok, Sup} = alinkiot_tdengine_sup:start_link(),
    alinkiot_tdengine_writer:start(),
    alinkiot_tdrestful:start(),
    load(),
    {ok, Sup}.

%%--------------------------------------------------------------------
stop(_State) ->
    unload(),
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

load() ->
    ok.

unload() ->
    ok.