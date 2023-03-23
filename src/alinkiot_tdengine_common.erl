%%%-------------------------------------------------------------------
%%% @author yqfclid
%%% @copyright (C) 2023, yuqinfeng17@gmail.com
%%% @doc
%%%
%%% @end
%%% Created : 22. 3月 2023 上午12:56
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_common).
-author("yqfclid").

%% API
-export([
    to_sql_bin/1,
    transform_field_type/1,
    to_td_field_name/1,
    from_td_field_name/1
]).

%%%===================================================================
%%% API
%%%===================================================================
to_sql_bin(V) when is_binary(V)->
    <<"'", V/binary, "'">>;
to_sql_bin(V) ->
    alinkutil_type:to_binary(V).


transform_field_type(<<"time">>) ->
    <<"TIMESTAMP">>;
transform_field_type(<<"int">>) ->
    <<"INT">>;
transform_field_type(<<"integer">>) ->
    <<"INT">>;
transform_field_type(<<"float">>) ->
    <<"FLOAT">>;
transform_field_type(<<"string">>) ->
    <<"VARCHAR(100)">>;
transform_field_type(Type) ->
    Type.


to_td_field_name(F) ->
    <<"alink_", F/binary>>.


from_td_field_name(<<"alink_", F/binary>>) ->
    F;
from_td_field_name(F) ->
    F.
%%%===================================================================
%%% Internal functions
%%%===================================================================