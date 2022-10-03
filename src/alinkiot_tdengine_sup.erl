-module(alinkiot_tdengine_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

-include("alinkiot_tdengine.hrl").

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).


init([]) ->
    ets:new(?WRITER_TAB, [set, named_table, public, {read_concurrency, true}]),
    {ok, {{one_for_all, 0, 1}, []}}.

