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
    alinkiot_tdengine_rest:start(),
    {ok, Sup} = alinkiot_tdengine_sup:start_link(),
    alinkiot_tdengine_worker:start_workers(),
    {ok, Sup}.

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================