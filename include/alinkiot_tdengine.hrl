%%%-------------------------------------------------------------------
%%% @author kenneth
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 26. 四月 2020 16:35
%%%-------------------------------------------------------------------
-author("kenneth").
-define(MAX_PROFILE, 100).
-define(TYPE, <<"TD">>).
-define(DEFAULT, <<"default">>).
-define(PRE, <<"_">>).
-define(Table(Name), <<?PRE/binary, Name/binary>>).
-define(Struct(Field, Field1), <<"struct_", Field/binary, "_", Field1/binary>>).

-define(TYPES, [
    <<"TIMESTAMP">>,
    <<"INT">>,
    <<"BIGINT">>,
    <<"FLOAT">>,
    <<"DOUBLE">>,
    <<"BINARY">>,
    <<"SMALLINT">>,
    <<"TINYINT">>,
    <<"BOOL">>,
    <<"NCHAR">>
]).

-define(ALINKIOT_TD_CH_WORK, alinkiot_td_ch_work).
-define(ALINKIOT_TD_CH_MODEL, alinkiot_td_ch_model).
