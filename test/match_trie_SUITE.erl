%% Copyright (c) 2016 Contributors as noted in the AUTHORS file
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
  [t_insert, t_match, t_match2, t_match3, t_delete, t_delete2, t_delete3].

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
