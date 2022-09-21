%%%-------------------------------------------------------------------
%%% @author yqfclid
%%% @copyright (C) 2022
%%% @doc
%%%
%%% @end
%%% Created : 19. 9月 2022 下午7:20
%%%-------------------------------------------------------------------
-module(alinkiot_tdengine_rest).
-author("yqfclid").


-export([
    simple_query/5,
    query/2,
    query/3,
    try_http_query/6,
    do_http_query/4
]).

simple_query(Host, Port, UserName, Passsword, Sql) ->
    HostB = to_binary(Host),
    PortB = to_binary(Port),
    UserNameB = to_binary(UserName),
    PassswordB = to_binary(Passsword),
    Url = <<"http://", HostB/binary, ":", PortB/binary, "rest/sql">>,
    query(Url, to_binary(Sql), #{username => UserNameB, password => PassswordB}).


query(Url, Sql) ->
    query(Url, Sql, #{username => <<"root">>, password => <<"taosdata">>}).



query(Url, Sql, #{authorization := Authorization} = QueryOpts) ->
    HttpOpts = [
        {pool, maps:get(pool, QueryOpts, default)},
        {connect_timeout, 10000},
        {recv_timeout, 30000},
        {follow_redirectm, true},
        {max_redirect, 5},
        with_body
    ],
    try_http_query(Url, Sql, Authorization, HttpOpts, undefined, maps:get(retry, QueryOpts, 1));
query(Url, Sql, #{username := Username, password := Password} = QueryOpts) ->
    Token = base64:encode(<<Username/binary, ":", Password/binary>>),
    query(Url, Sql, QueryOpts#{authorization => <<"Basic ", Token/binary>>}).


try_http_query(_Url, _Sql, _Authorization, _HttpOpts, Err, 0) ->
    Err;
try_http_query(Url, Sql, Authorization, HttpOpts, _Err, Retry) ->
    case do_http_query(Url, Authorization, Sql, HttpOpts) of
        {ok, Return} ->
            {ok, Return};
        {error, Reason} ->
            try_http_query(Url, Sql, Authorization, HttpOpts, {error, Reason}, Retry - 1)
    end.





do_http_query(Url, Authorization, Sql, HttpOpts) ->
    Headers = [{<<"Authorization">>, Authorization}],
    case hackney:request(post, Url, Headers, Sql, HttpOpts) of
        {ok, StatusCode, _Headers, ResponseBody}
            when StatusCode =:= 200 orelse StatusCode =:= 204 ->
            case jiffy:decode(ResponseBody, [return_maps]) of
                #{<<"status">> := <<"succ">>} = ResponseMap -> {ok, ResponseMap};
                ResponseMap -> {error, ResponseMap}
            end;
        {ok, StatusCode, _Headers, ResponseBody} ->
            {error,
                {StatusCode, jiffy:decode(ResponseBody, [return_maps])}};
        {error, Reason} -> {error, Reason}
    end.




to_binary(S) when is_atom(S) ->
    atom_to_binary(S);
to_binary(S) when is_list(S) ->
    list_to_binary(S);
to_binary(S) when is_integer(S) ->
    integer_to_binary(S);
to_binary(S) when is_float(S) ->
    float_to_binary(S);
to_binary(S) when is_binary(S) ->
    S;
to_binary(S) ->
    throw({badarg, S}).
