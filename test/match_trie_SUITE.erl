%% Copyright (c) 2016-2026 Benoit Chesneau
%%
%% This file is part match_trie
%%
%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at http://mozilla.org/MPL/2.0/.

-module(match_trie_SUITE).

-compile(export_all).

-include("match_trie.hrl").

-define(TRIE, match_trie).

all() ->
  [t_insert, t_match, t_match2, t_match3, t_delete, t_delete2, t_delete3,
   t_new_access, t_new_badarg, t_insert_badarg,
   t_validate, t_is_wildcard, t_is_match].

init_per_suite(Config) ->
  Config.

end_per_suite(Config) ->
  Config.

init_per_testcase(_TestCase, Config) ->
  Config.

end_per_testcase(_TestCase, Config) ->
  Config.

t_insert(_Config) ->
  Trie = ?TRIE:new(),
  TN = #trie_node{node_id = <<"db">>,
    edge_count = 3,
    topic = <<"db">>,
    flags = undefined},

  ?TRIE:insert(Trie, <<"db/1/metric/2">>),
  ?TRIE:insert(Trie, <<"db/+/#">>),
  ?TRIE:insert(Trie, <<"db/#">>),
  ?TRIE:insert(Trie, <<"db">>),
  ?TRIE:insert(Trie, <<"db">>),
  [TN] = ?TRIE:lookup(Trie, <<"db">>),
  ?TRIE:delete(Trie).

t_match(_Config) ->
  Trie = ?TRIE:new(),
  Machted = [<<"db/+/#">>, <<"db/#">>],
  ?TRIE:insert(Trie, <<"db/1/metric/2">>),
  ?TRIE:insert(Trie, <<"db/+/#">>),
  ?TRIE:insert(Trie, <<"db/#">>),
  Machted = ?TRIE:match(Trie, <<"db/1">>),
  ?TRIE:delete(Trie).

t_match2(_Config) ->
  Trie = ?TRIE:new(),
  Matched = {[<<"+/+/#">>, <<"+/#">>, <<"#">>], []},
  ?TRIE:insert(Trie, <<"#">>),
  ?TRIE:insert(Trie, <<"+/#">>),
  ?TRIE:insert(Trie, <<"+/+/#">>),

  Matched = {?TRIE:match(Trie, <<"a/b/c">>),
    ?TRIE:match(Trie, <<"$SYS/config/httpd">>)},
  ?TRIE:delete(Trie).

t_match3(_Config) ->
  Trie = ?TRIE:new(),
  Topics = [<<"d/#">>, <<"a/b/c">>, <<"a/b/+">>, <<"a/#">>, <<"#">>, <<"$SYS/#">>],
  [?TRIE:insert(Trie, Topic) || Topic <- Topics],
  Matched = ?TRIE:match(Trie, <<"a/b/c">>),
  4 = length(Matched),
  SysMatched = ?TRIE:match(Trie, <<"$SYS/a/b/c">>),
  [<<"$SYS/#">>] = SysMatched,
  ?TRIE:delete(Trie).

t_delete(_Config) ->
  Trie = ?TRIE:new(),
  TN = #trie_node{node_id = <<"db/1">>,
    edge_count = 2,
    topic = undefined,
    flags = undefined},

  ?TRIE:insert(Trie, <<"db/1/#">>),
  ?TRIE:insert(Trie, <<"db/1/metric/2">>),
  ?TRIE:insert(Trie, <<"db/1/metric/3">>),
  ?TRIE:delete(Trie, <<"db/1/metric/2">>),
  ?TRIE:delete(Trie, <<"db/1/metric">>),
  ?TRIE:delete(Trie, <<"db/1/metric">>),
  [TN] = ?TRIE:lookup(Trie, <<"db/1">>),
  ?TRIE:delete(Trie).

t_delete2(_Config) ->
  Trie = ?TRIE:new(),
  ?TRIE:insert(Trie, <<"db">>),
  ?TRIE:insert(Trie, <<"db/1/metric/2">>),
  ?TRIE:insert(Trie, <<"db/1/metric/3">>),
  ?TRIE:delete(Trie, <<"db">>),
  ?TRIE:delete(Trie, <<"db/1/metric/2">>),
  ?TRIE:delete(Trie, <<"db/1/metric/3">>),
  {[], []} = {?TRIE:lookup(Trie, <<"db">>), ?TRIE:lookup(Trie, <<"db/1">>)},
  ?TRIE:delete(Trie).

t_delete3(_Config) ->
  Trie = ?TRIE:new(),
  ?TRIE:insert(Trie, <<"db/+">>),
  ?TRIE:insert(Trie, <<"db/+/metric/2">>),
  ?TRIE:insert(Trie, <<"db/+/metric/3">>),
  ?TRIE:delete(Trie, <<"db/+/metric/2">>),
  ?TRIE:delete(Trie, <<"db/+/metric/3">>),
  ?TRIE:delete(Trie, <<"db">>),
  ?TRIE:delete(Trie, <<"db/+">>),
  ?TRIE:delete(Trie, <<"db/+/unknown">>),
  {[], []} = {?TRIE:lookup(Trie, <<"db">>), ?TRIE:lookup(Trie, <<"db/+">>)},
  ?TRIE:delete(Trie).

t_new_access(_Config) ->
  Trie1 = ?TRIE:new(private),
  ?TRIE:insert(Trie1, <<"test">>),
  [<<"test">>] = ?TRIE:match(Trie1, <<"test">>),
  ?TRIE:delete(Trie1),
  Trie2 = ?TRIE:new(public),
  ?TRIE:insert(Trie2, <<"test">>),
  [<<"test">>] = ?TRIE:match(Trie2, <<"test">>),
  ?TRIE:delete(Trie2).

t_new_badarg(_Config) ->
  try
    ?TRIE:new(invalid),
    error(should_fail)
  catch
    error:badarg -> ok
  end.

t_insert_badarg(_Config) ->
  Trie = ?TRIE:new(),
  try
    ?TRIE:insert(Trie, not_binary),
    error(should_fail)
  catch
    error:badarg -> ok
  end,
  ?TRIE:delete(Trie).

t_validate(_Config) ->
  %% Empty topic is invalid
  false = ?TRIE:validate({name, <<>>}),
  false = ?TRIE:validate({filter, <<>>}),
  %% Topic too long
  LongTopic = binary:copy(<<"a">>, 4097),
  false = ?TRIE:validate({name, LongTopic}),
  false = ?TRIE:validate({filter, LongTopic}),
  %% Valid filter with wildcards
  true = ?TRIE:validate({filter, <<"a/+/b">>}),
  true = ?TRIE:validate({filter, <<"a/#">>}),
  true = ?TRIE:validate({filter, <<"#">>}),
  true = ?TRIE:validate({filter, <<"+/+">>}),
  %% Valid name (no wildcards)
  true = ?TRIE:validate({name, <<"a/b/c">>}),
  true = ?TRIE:validate({name, <<"test">>}),
  %% Name with wildcard is invalid
  false = ?TRIE:validate({name, <<"a/+/b">>}),
  false = ?TRIE:validate({name, <<"a/#">>}),
  %% Invalid: # not at end
  false = ?TRIE:validate({filter, <<"a/#/b">>}),
  %% Invalid: contains # or + in word
  false = ?TRIE:validate({filter, <<"a/b#c">>}),
  false = ?TRIE:validate({filter, <<"a/b+c">>}),
  %% Invalid: contains null character
  false = ?TRIE:validate({filter, <<"a/b", 0, "c">>}),
  %% Valid empty segments
  true = ?TRIE:validate({filter, <<"a//b">>}),
  true = ?TRIE:validate({name, <<"a//b">>}).

t_is_wildcard(_Config) ->
  %% Binary input
  true = ?TRIE:is_wildcard(<<"a/+/b">>),
  true = ?TRIE:is_wildcard(<<"a/#">>),
  true = ?TRIE:is_wildcard(<<"#">>),
  true = ?TRIE:is_wildcard(<<"+/a">>),
  false = ?TRIE:is_wildcard(<<"a/b/c">>),
  false = ?TRIE:is_wildcard(<<"test">>),
  %% List input (words)
  true = ?TRIE:is_wildcard([<<"a">>, '+', <<"b">>]),
  true = ?TRIE:is_wildcard(['#']),
  false = ?TRIE:is_wildcard([<<"a">>, <<"b">>]),
  false = ?TRIE:is_wildcard([]).

t_is_match(_Config) ->
  %% Exact match
  true = ?TRIE:is_match(<<"a/b/c">>, <<"a/b/c">>),
  false = ?TRIE:is_match(<<"a/b/c">>, <<"a/b/d">>),
  %% Single-level wildcard
  true = ?TRIE:is_match(<<"a/b/c">>, <<"a/+/c">>),
  true = ?TRIE:is_match(<<"a/b/c">>, <<"+/+/+">>),
  false = ?TRIE:is_match(<<"a/b">>, <<"a/+/c">>),
  %% Multi-level wildcard
  true = ?TRIE:is_match(<<"a/b/c">>, <<"a/#">>),
  true = ?TRIE:is_match(<<"a/b/c/d">>, <<"a/#">>),
  true = ?TRIE:is_match(<<"a">>, <<"#">>),
  %% $ prefix handling (system topics)
  false = ?TRIE:is_match(<<"$SYS/broker">>, <<"+/broker">>),
  false = ?TRIE:is_match(<<"$SYS/broker">>, <<"#">>),
  true = ?TRIE:is_match(<<"$SYS/broker">>, <<"$SYS/+">>),
  true = ?TRIE:is_match(<<"$SYS/broker">>, <<"$SYS/#">>),
  %% Length mismatch
  false = ?TRIE:is_match(<<"a/b/c">>, <<"a/b">>),
  false = ?TRIE:is_match(<<"a/b">>, <<"a/b/c">>),
  %% Empty segments
  true = ?TRIE:is_match(<<"a//b">>, <<"a//b">>),
  true = ?TRIE:is_match(<<"a//b">>, <<"a/+/b">>).
