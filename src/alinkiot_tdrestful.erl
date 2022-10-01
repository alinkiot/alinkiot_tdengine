-module(alinkiot_tdrestful).
-author("kenneth").
-include("alinkiot_tdengine.hrl").
-define(HTTPOption, [{timeout, 60000}, {connect_timeout, 60000}]).
-define(REQUESTOption, [{body_format, binary}]).
-export([start/0, show_database/3]).
-export([request/4, do_request/3]).


show_database(Url, UserName, Password) ->
    request(Url, UserName, Password, <<"SHOW DATABASES;">>).


%% Base64
request(Url, UserName, Password, Sql) ->
    Authorization = lists:concat(["Basic ", binary_to_list(base64:encode(<<UserName/binary, ":", Password/binary>>))]),
    do_request(Url, Authorization, Sql).

%% 如果自定义 Authorization: Taosd <TOKEN>
do_request(Url, Authorization, Sql) when is_binary(Url) ->
    do_request(binary_to_list(Url), Authorization, Sql);

do_request(Url, Authorization, Sql) when is_binary(Authorization) ->
    do_request(Url, binary_to_list(Authorization), Sql);

do_request(Url, Authorization, Sql) when is_binary(Sql) ->
    do_request(Url, Authorization, binary_to_list(Sql));

do_request(Url, Authorization, Sql) ->
    Header = [{"Authorization", Authorization}],
    {Sql1, Formatter} =
        case re:run(Sql, <<"tbname\s+as\s+([^\s,]+)">>, [{capture, all_but_first, binary}]) of
            {match, [As]} ->
                {re:replace(Sql, <<"tbname\s+as\s+[^\s,]+">>, <<"tbname">>, [{return, binary}]), #{<<"tbname">> => As}};
            _ ->
                {Sql, #{}}
        end,
    Request = {Url, Header, "text/sql", Sql1},
    Index = random:uniform(?MAX_PROFILE),
    Profile = list_to_atom(lists:concat([http, Index])),
    timer:sleep(1),
    case catch httpc:request(post, Request, ?HTTPOption, ?REQUESTOption, Profile) of
        {ok, {{_HTTPVersion, StatusCode, _ReasonPhrase}, _Headers, Body}} ->
            format_body(StatusCode, Body, Formatter);
        {error, {failed_connect, _}} ->
            {error, disconnect};
        {'EXIT', {noproc, {gen_server, call, [_ | _]}}} ->
            {error, <<"httpc_not_start">>};
        {Err, Reason} when Err == error; Err == 'EXIT' ->
            {error, Reason}
    end.


%% head: 表的定义，如果不返回结果集，仅有一列“affected_rows”
%% 返回受影响行数
format_body(_StatusCode, #{
    <<"status">> := <<"succ">>,
    <<"head">> := [<<"affected_rows">>],
    <<"data">> := [[AffectedRows]]
}, _Formatter) ->
    {ok, #{<<"affected_rows">> => AffectedRows}};

format_body(_StatusCode, #{
    <<"head">> := [<<"count(*)">>],
    <<"data">> := [[Count]]
}, _Formatter) ->
    {ok, #{<<"count">> => Count}};

%% 返回结果集
format_body(_StatusCode, #{
    <<"status">> := <<"succ">>,
    <<"head">> := Fields,
    <<"data">> := Rows
}, Formatter) ->
    Result = [format_head(Fields, Row, #{}, Formatter) || Row <- Rows],
    {ok, #{<<"results">> => Result}};

format_body(_StatusCode, #{<<"status">> := <<"error">>, <<"code">> := Code, <<"desc">> := Reason}, _Formatter) ->
    {error, #{<<"code">> => Code, <<"desc">> => Reason}};
format_body(StatusCode, Body, Formatter) when is_binary(Body) ->
    format_body(StatusCode, jsx:decode(Body, [ {labels, binary},return_maps]), Formatter);
format_body(_StatusCode, Body, _Formatter) ->
    {ok, Body}.


format_head([], [], Acc, _Formatter) -> Acc;
format_head([<<"struct_", H/binary>> | Headers], [V | Values], Acc, Formatter) ->
    [P, S] = re:split(H, <<"_">>),
    Parent = maps:get(P, Acc, #{}),
    format_head(Headers, Values, Acc#{P => Parent#{S => V}}, Formatter);

format_head([H | Headers], [V1 | Values], Acc, Formatter) when H == <<"tbname">>; H == <<"TBNAME">> ->
    case maps:get(<<"tbname">>, Formatter, undefined) of
        undefined ->
            format_head(Headers, Values, Acc#{H => re:replace(V1, ?PRE, <<>>, [{return, binary}])}, Formatter);
        NewH ->
            format_head(Headers, Values, Acc#{NewH => re:replace(V1, ?PRE, <<>>, [{return, binary}])}, Formatter)
    end;

format_head([H0 | Headers], [V | Values], Acc, Formatter) ->
    case re:run(H0, <<"last_row\\(([^\\)]+)\\)">>, [{capture, all_but_first, binary}]) of
        {match, [H]} ->
            format_head([H | Headers], [V | Values], Acc, Formatter);
        _ ->
            format_head(Headers, Values, Acc#{H0 => V}, Formatter)
    end.
