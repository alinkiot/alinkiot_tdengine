-module(alinkiot_tdengine_app).

-behaviour(application).

-emqx_plugin(?MODULE).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    {ok, Sup} = alinkiot_tdengine_sup:start_link(),
    alinkiot_tdrestful:start(),
    {ok, Sup}.

stop(_State) ->
    ok.
