%%
%% This file is part of Triq - Trifork QuickCheck
%%
%% Copyright (c) 2010 by Trifork
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%  
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%

%%
%% Remote equivalence tests for erjang/erlang
%% name of remote server is given with -other NAME
%% on command line (assumed to be localhost).
%%

% ../../../ej -sname erj@mcilroy -pz ~/OSS/triq/ebin/ -other erl 
% c(ets_test, [{i, "/home/erik/OSS/triq/include"}]).
% ets_test:main().

% Other:
% erl -pz ~/OSS/triq/ebin/ -sname erl

-module(ets_test).

-include("triq.hrl").

-export([main/0, ets_behaviour/1, ets_behaviour_wrapper/1]).


%% ===========================================
%% 
%% ===========================================
host([$@|Rest]) ->
    Rest;
host([_|T]) ->
    host(T).
host() ->
    host(atom_to_list(node())).

server() ->
    {ok,[[Other]]} = init:get_argument(other),
    list_to_atom(Other++[$@|host()]).

call(Node,Mod,Fun,Args) ->
    case rpc:call(Node, Mod,Fun,Args) of
	{badrpc,{'EXIT',{Reason,[FirstTrace|_]}}} ->
	    {badrpc, {'EXIT',{Reason,[FirstTrace]}}};
	Value -> Value
    end.    

%% ===========================================
%% Run Mod:Fun(Args) on beam
%% ===========================================
other(Mod,Fun,Args) when is_atom(Mod), is_atom(Fun), is_list(Args) ->
    call(server(), Mod,Fun,Args).

other(Fun,Args) when is_list(Args) ->
    call(server(), erlang,Fun,Args).

ets_behaviour_wrapper(Prg) ->
    process_flag(trap_exit, true),
    io:format("ets_behaviour_wrapper: Prg=~p\n", [Prg]),
    try
	ets_behaviour(Prg)
   after [catch(ets:delete(T)) || T <- [table1, table2]]
   end.

ets_behaviour([]) -> [];
ets_behaviour([Cmd | Rest]) ->
    try ets_do(Cmd) of
	Res -> [{ok, Res} | ets_behaviour(Rest)]
    catch A:B ->
	    {error, A, B,
	     [scrub(catch(lists:sort(ets:tab2list(T)))) || T <- [table1, table2]]}
    end.

scrub({'EXIT', {R, ST}}) -> {'EXIT', {R, hd(ST)}}; % Interpreter stacktraces aren't to be relied upon.
scrub(X) -> X.


ets_do({new, Name, Options}) -> ets:new(Name, [named_table | Options]);
ets_do({insert, Tab, Item})  -> ets:insert(Tab, Item);
ets_do({insert_new, Tab, Item}) -> ets:insert_new(Tab, Item);
ets_do({lookup, Tab, Key}) -> ets:lookup(Tab, Key);
ets_do({lookup_element, Tab, Key, Pos}) -> ets:lookup_element(Tab, Key, Pos);
ets_do({delete, Tab}) -> ets:delete(Tab);
ets_do({delete, Tab, Key}) -> ets:delete(Tab, Key).


%% ===========================================
%% Run erlang:Fun(Args) here
%% ===========================================
here(Mod,Fun,Args) ->
    call(node(),Mod,Fun,Args).
here(Fun,Args) ->
    call(node(),erlang,Fun,Args).



%% ===========================================
%% Property test for binary operators
%% ===========================================
prop_binop() ->
    ?FORALL({A,B,OP}, 
	    {xany(),xany(),
	     elements(['>', '<', 
		       '==', '=:=', '/=', 
		       '=<', '>=', 
		       '++',
		       '+', '-', '/', '*', 'div',
%		       'bsl', 'bsr',
		       'or'
		      ])},
	    begin
		Here  = here(OP,[A,B]),
		There = other(OP,[A,B]),
		?WHENFAIL(io:format("here=~p~nthere=~p~n~n", [Here,There]),
			  Here == There)
	    end).

smaller(Domain) ->
%    ?SIZED(SZ, triq_dom:resize(random:uniform((SZ div 2)+1), Domain)).
    ?SIZED(SZ, triq_dom:resize(random:uniform(round(math:sqrt(SZ)+1)), Domain)).

-define(MIN_INT32, (-(1 bsl 31))).
-define(MAX_INT32, ((1 bsl 31))).

-define(MIN_INT64, (-(1 bsl 63))).
-define(MAX_INT64, ((1 bsl 63))).

table_name() ->
    oneof([table1, table2]).

table_key() ->
    oneof([key1, "key2", 123, 123.0, smaller(?DELAY(any()))]).

table_tuple() ->
    ?LET({K,L}, {table_key(), list(smaller(?DELAY(any())))},
	 list_to_tuple([K | L])).

table_type() ->
%%     oneof([set, bag, duplicate_bag, ordered_set]).
    oneof([set, ordered_set]).

ets_cmd() ->
    oneof([{new, ?DELAY(table_name()), [table_type()]},
	   {insert, table_name(), table_tuple()},
	   {insert_new, table_name(), table_tuple()},
	   {lookup, table_name(), table_key()},
	   {lookup_element, table_name(), table_key(), smaller(?DELAY(int()))},
	   {delete, table_name()},
	   {delete, table_name(), table_key()}]).


ets_program() ->
    list(ets_cmd()).

xany()  ->
    oneof([int(), real(), bool(), atom(), 

	   %% also test integers around +/- MIN_INT32 limits
	   choose(?MIN_INT32-10, ?MIN_INT32+10),
	   choose(?MAX_INT32-10, ?MAX_INT32+10),

	   %% also test integers around +/- MIN_INT64 limits
	   choose(?MIN_INT64-10, ?MIN_INT64+10),
	   choose(?MAX_INT64-10, ?MAX_INT64+10),

	   [smaller(?DELAY(any())) | smaller(?DELAY(any()))],

	   %% list(any()), but with a size in the range 1..GenSize
	   list(smaller(?DELAY(any()))),

	   tuple(smaller(?DELAY(any())))

	  ]).

prop_same_ets_behaviour() ->
    ?FORALL(X, ets_program(),
	    begin
		timer:sleep(400),
		Here = here(?MODULE, ets_behaviour_wrapper, [X]),
		There = other(?MODULE, ets_behaviour_wrapper, [X]),
		if Here /= There -> io:format("Diff: here=~p,\n     there=~p~n", [Here,There]); true -> ok end,
		Here==There
	    end).

%%
%% run the test
%%
main() ->
    triq:check(prop_same_ets_behaviour()).

