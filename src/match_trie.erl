%% Copyright (c) 2016-2026 Benoit Chesneau
%%
%% This file is part match_trie
%%
%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at http://mozilla.org/MPL/2.0/.

%% @doc A trie data structure for matching MQTT-style topic patterns.
%%
%% This module implements a trie (prefix tree) using ETS tables for efficient
%% storage and lookup of topic patterns with wildcard support. It is designed
%% for use cases like MQTT topic matching, routing keys, or any hierarchical
%% path matching system.
%%
%% == Topic Format ==
%%
%% Topics are binary strings with segments separated by `/'. For example:
%% `<<"sensors/temperature/room1">>'.
%%
%% == Wildcards ==
%%
%% Two wildcards are supported:
%%
%% `+' (single-level): Matches exactly one topic segment.
%% For example, "sensors/+/room1" matches "sensors/temperature/room1"
%% but not "sensors/temperature/floor1/room1".
%%
%% `#' (multi-level): Matches zero or more topic segments.
%% Must be the last segment. For example, "sensors/#" matches
%% "sensors", "sensors/temperature", and "sensors/temperature/room1".
%%
%% == System Topics ==
%%
%% Topics starting with `$' (like `<<"$SYS/...">>' in MQTT) are treated specially.
%% They are not matched by `+' or `#' wildcards at the root level.
%%
%% == Quick Start ==
%%
%% ```
%% %% Create a new trie
%% Trie = match_trie:new(),
%%
%% %% Insert topic patterns
%% ok = match_trie:insert(Trie, <<"sensors/+/temperature">>),
%% ok = match_trie:insert(Trie, <<"sensors/#">>),
%%
%% %% Find matching patterns
%% Matches = match_trie:match(Trie, <<"sensors/room1/temperature">>),
%% %% Returns: [<<"sensors/+/temperature">>, <<"sensors/#">>]
%%
%% %% Clean up
%% ok = match_trie:delete(Trie).
%% '''
%%
%% == Concurrency ==
%%
%% The trie uses ETS tables internally. By default, tables are created with
%% `protected' access, allowing concurrent reads from other processes.
%% Use {@link new/1} to specify different access modes.
%%
%% @end
-module(match_trie).

-author("benoitc").

-export([new/0, new/1, insert/2, match/2, delete/1, delete/2]).
-export([lookup/2]).
-export([validate/1, is_match/2,  is_wildcard/1]).

-include("match_trie.hrl").

-record(trie_tree, {ntab = notable :: ets:tab(),
  ttab = notable :: ets:tab()}).


-type topic() :: binary().
%% A topic is a binary string with segments separated by `/'.
%% Example: `<<"sensors/temperature/room1">>'.

-type word() :: '' | '+' | '#' | binary().
%% A single segment of a topic. Empty binary becomes `''',
%% `<<"+">> becomes `+', and `<<"#">> becomes `#'.

-type words() :: list(word()).
%% A topic split into its constituent segments.

-opaque trie() :: #trie_tree{}.
%% An opaque reference to the trie data structure.
%% Created by {@link new/0} or {@link new/1}.

-export_type([trie/0, topic/0]).

-define(MAX_TOPIC_LEN, 4096).

%% @doc Create a new trie with protected access.
%%
%% Equivalent to `new(protected)'. The trie can be read by other processes
%% but only written by the creating process.
%%
%% @see new/1
-spec new() -> trie().
new() -> new(protected).

%% @doc Create a new trie with the specified ETS access mode.
%%
%% Access modes:
%%
%% `private' - Only the creating process can read or write.
%%
%% `protected' - Any process can read, only creator can write.
%%
%% `public' - Any process can read or write.
%%
%% Example:
%% ```
%% Trie = match_trie:new(public).
%% '''
%%
%% Raises `error:badarg' if Access is not a valid access mode.
-spec new(Access) -> trie() when
  Access :: private | protected | public.
new(Access) ->
  case lists:member(Access, [protected, private, public]) of
    true ->
      T = ets:new(trie,  [ordered_set, Access,
        {keypos, #trie.edge}]),
      N = ets:new(trie_node, [ordered_set, Access,
        {keypos, #trie_node.node_id}]),
      #trie_tree{ntab=N, ttab=T};
    false ->
      erlang:error(badarg)
  end.

%% @doc Insert a topic pattern into the trie.
%%
%% The topic can include wildcards (`+' and `#'). Inserting the same
%% topic multiple times has no effect.
%%
%% Example:
%% ```
%% ok = match_trie:insert(Trie, <<"sensors/+/temperature">>),
%% ok = match_trie:insert(Trie, <<"sensors/#">>).
%% '''
%%
%% Raises `error:badarg' if Topic is not a binary.
-spec insert(Trie, Topic) -> ok when
  Trie :: trie(),
  Topic :: topic().
insert(T, Topic) when is_binary(Topic) ->
  NT = T#trie_tree.ntab,
  case ets:lookup(NT, Topic) of
    [#trie_node{topic=Topic}] ->
      ok;
    [TrieNode=#trie_node{topic=undefined}] ->
      true = ets:insert(NT, TrieNode#trie_node{topic=Topic}),
      ok;
    [] ->
      Fun = fun(Triple) ->  add_path(Triple, T) end,
      lists:foreach(Fun, triples(Topic)),
      true = ets:insert(NT, #trie_node{node_id=Topic, topic=Topic}),
      ok
  end;
insert(_, _) ->
  erlang:error(badarg).

%% @doc Find all topic patterns that match the given topic.
%%
%% Returns a list of all previously inserted patterns that match the topic.
%% The topic itself should not contain wildcards; it represents a concrete
%% topic name to match against stored patterns.
%%
%% Example:
%% ```
%% %% After inserting <<"sensors/+/#">> and <<"sensors/room1/temperature">>
%% Matches = match_trie:match(Trie, <<"sensors/room1/temperature">>).
%% %% Returns: [<<"sensors/+/#">>, <<"sensors/room1/temperature">>]
%% '''
-spec match(Trie, Topic) -> [topic()] when
  Trie :: trie(),
  Topic :: topic().
match(T, Topic) when is_binary(Topic) ->
  TrieNodes = match_node(root, words(Topic), T),
  [Name || #trie_node{topic=Name} <- TrieNodes, Name =/= undefined].


%% @doc Delete the entire trie and free its resources.
%%
%% This destroys the ETS tables backing the trie. The trie reference
%% becomes invalid after this call.
%%
%% Example:
%% ```
%% ok = match_trie:delete(Trie).
%% '''
-spec delete(Trie) -> ok when
  Trie :: trie().
delete(#trie_tree{ntab=NT, ttab=TT}) ->
  true = ets:delete(NT),
  true = ets:delete(TT),
  ok.

%% @doc Remove a topic pattern from the trie.
%%
%% If the topic does not exist in the trie, this is a no-op.
%%
%% Example:
%% ```
%% ok = match_trie:delete(Trie, <<"sensors/+/temperature">>).
%% '''
-spec delete(Trie, Topic) -> ok when
  Trie :: trie(),
  Topic :: topic().
delete(T, Topic) when is_binary(Topic) ->
  NT = T#trie_tree.ntab,
  case ets:lookup(NT, Topic) of
    [#trie_node{edge_count=0}] ->
      ets:delete(NT, Topic),
      delete_path(lists:reverse(triples(Topic)), T),
      ok;
    [TrieNode] ->
      ets:insert(NT, TrieNode#trie_node{topic=undefined}),
      ok;
    [] ->
      ok
  end.

%% @doc Look up a trie node by its ID.
%%
%% This is a low-level function that returns the internal trie node record.
%% Most users should use {@link match/2} instead.
-spec lookup(Trie, NodeId) -> [#trie_node{}] when
  Trie :: trie(),
  NodeId :: binary().
lookup(T, NodeId) ->
  ets:lookup(T#trie_tree.ntab, NodeId).

%% @doc Validate a topic name or filter.
%%
%% Checks if a topic is well-formed according to MQTT-style rules.
%% Topics must not be empty, must not exceed 4096 bytes, the `#' wildcard
%% must only appear at the end, wildcards must occupy entire segments
%% (not embedded like "a+b"), and no null characters are allowed.
%%
%% Use `{filter, Topic}' to validate subscription filters (wildcards allowed).
%% Use `{name, Topic}' to validate topic names (no wildcards allowed).
%%
%% Example:
%% ```
%% true = match_trie:validate({filter, <<"sensors/+/temperature">>}),
%% true = match_trie:validate({name, <<"sensors/room1/temperature">>}),
%% false = match_trie:validate({name, <<"sensors/+/temperature">>}).
%% '''
-spec validate({name | filter, Topic}) -> boolean() when
  Topic :: topic().
validate({_, <<>>}) ->
  false;
validate({_, Topic}) when is_binary(Topic) and (size(Topic) > ?MAX_TOPIC_LEN) ->
  false;
validate({filter, Topic}) when is_binary(Topic) ->
  validate2(words(Topic));
validate({name, Topic}) when is_binary(Topic) ->
  Words = words(Topic),
  validate2(Words) and (not is_wildcard(Words)).

validate2([]) ->
  true;
validate2(['#']) -> % end with '#'
  true;
validate2(['#'|Words]) when length(Words) > 0 ->
  false;
validate2([''|Words]) ->
  validate2(Words);
validate2(['+'|Words]) ->
  validate2(Words);
validate2([W|Words]) ->
  case validate3(W) of
    true -> validate2(Words);
    false -> false
  end.

validate3(<<>>) ->
  true;
validate3(<<C/utf8, _Rest/binary>>) when C == $#; C == $+; C == 0 ->
  false;
validate3(<<_/utf8, Rest/binary>>) ->
  validate3(Rest).


%% @doc Check if a topic contains wildcards.
%%
%% Returns `true' if the topic contains `+' or `#' wildcards.
%%
%% Example:
%% ```
%% true = match_trie:is_wildcard(<<"sensors/+/temperature">>),
%% true = match_trie:is_wildcard(<<"sensors/#">>),
%% false = match_trie:is_wildcard(<<"sensors/room1/temperature">>).
%% '''
-spec is_wildcard(Topic) -> boolean() when
  Topic :: topic() | words().
is_wildcard(Topic) when is_binary(Topic) ->
  is_wildcard(words(Topic));
is_wildcard([]) ->
  false;
is_wildcard(['#'|_]) ->
  true;
is_wildcard(['+'|_]) ->
  true;
is_wildcard([_H|T]) ->
  is_wildcard(T).

%% @doc Check if a topic name matches a filter pattern.
%%
%% Tests whether `Name' would be matched by the filter `Filter'.
%% Unlike {@link match/2}, this does not require a trie and works
%% directly on two topics.
%%
%% System topics (starting with `$') are not matched by `+' or `#'
%% wildcards at the root level.
%%
%% Example:
%% ```
%% true = match_trie:is_match(<<"sensors/room1/temp">>, <<"sensors/+/temp">>),
%% true = match_trie:is_match(<<"sensors/room1/temp">>, <<"sensors/#">>),
%% false = match_trie:is_match(<<"$SYS/broker">>, <<"#">>),
%% true = match_trie:is_match(<<"$SYS/broker">>, <<"$SYS/#">>).
%% '''
-spec is_match(Name, Filter) -> boolean() when
  Name :: topic() | words(),
  Filter :: topic() | words().
is_match(Name, Filter) when is_binary(Name) and is_binary(Filter) ->
  is_match(words(Name), words(Filter));
is_match([], []) ->
  true;
is_match([H|T1], [H|T2]) ->
  is_match(T1, T2);
is_match([<<$$, _/binary>>|_], ['+'|_]) ->
  false;
is_match([_H|T1], ['+'|T2]) ->
  is_match(T1, T2);
is_match([<<$$, _/binary>>|_], ['#']) ->
  false;
is_match(_, ['#']) ->
  true;
is_match([_H1|_], [_H2|_]) ->
  false;
is_match([_H1|_], []) ->
  false;
is_match([], [_H|_T2]) ->
  false.

%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------

%% @private
%% @doc Add path to trie tree.
add_path({Node, Word, Child}, T) ->
  NT = T#trie_tree.ntab,
  TT = T#trie_tree.ttab,

  Edge = #trie_edge{node_id=Node, word=Word},
  case ets:lookup(NT, Node) of
    [TrieNode = #trie_node{edge_count=Count}] ->
      case ets:lookup(TT, Edge) of
        [] ->
          ets:insert(NT, TrieNode#trie_node{edge_count=Count+1}),
          ets:insert(TT, #trie{edge=Edge, node_id=Child});
        [_] ->
          ok
      end;
    [] ->
      ets:insert(NT, #trie_node{node_id=Node, edge_count=1}),
      ets:insert(TT, #trie{edge=Edge, node_id=Child})
  end.

%% @private
%% @doc Match node with word or '+'.
match_node(root, [<<"$SYS">>|Words], T) ->
  match_node(<<"$SYS">>, Words, T, []);

match_node(NodeId, Words, T) ->
  match_node(NodeId, Words, T, []).


match_node(NodeId, [], T, ResAcc) ->
  ets:lookup(T#trie_tree.ntab, NodeId) ++ 'match_#'(NodeId, ResAcc, T);

match_node(NodeId, [W|Words], T, ResAcc) ->
  TT = T#trie_tree.ttab,
  lists:foldl(fun(WArg, Acc) ->
    case ets:lookup(TT, #trie_edge{node_id=NodeId, word=WArg}) of
      [#trie{node_id=ChildId}] -> match_node(ChildId, Words, T, Acc);
      [] -> Acc
    end
              end, 'match_#'(NodeId, ResAcc, T), [W, '+']).

%% @private
%% @doc Match node with '#'.
'match_#'(NodeId, ResAcc, T) ->
  NT = T#trie_tree.ntab,
  TT = T#trie_tree.ttab,
  case ets:lookup(TT, #trie_edge{node_id=NodeId, word = '#'}) of
    [#trie{node_id=ChildId}] ->
      ets:lookup(NT, ChildId) ++ ResAcc;
    [] ->
      ResAcc
  end.

%% @private
%% @doc Delete paths from trie tree.
delete_path([], _T) ->
  ok;
delete_path([{NodeId, Word, _} | RestPath], T) ->
  NT = T#trie_tree.ntab,
  TT = T#trie_tree.ttab,

  ets:delete(TT, #trie_edge{node_id=NodeId, word=Word}),
  case ets:lookup(NT, NodeId) of
    [#trie_node{edge_count=1, topic=undefined}] ->
      ets:delete(NT, NodeId),
      delete_path(RestPath, T);
    [TrieNode=#trie_node{edge_count=1, topic=_}] ->
      ets:insert(NT, TrieNode#trie_node{edge_count=0});
    [TrieNode=#trie_node{edge_count=C}] ->
      ets:insert(NT, TrieNode#trie_node{edge_count=C-1});
    [] ->
      throw({notfound, NodeId})
  end.



join(root, W) ->
  bin(W);
join(Parent, W) ->
  <<(bin(Parent))/binary, $/, (bin(W))/binary>>.

bin('')  -> <<>>;
bin('+') -> <<"+">>;
bin('#') -> <<"#">>;
bin(B) when is_binary(B) -> B.

triples(Topic) when is_binary(Topic) ->
  triples(words(Topic), root, []).

triples([], _Parent, Acc) ->
  lists:reverse(Acc);

triples([W|Words], Parent, Acc) ->
  Node = join(Parent, W),
  triples(Words, Node, [{Parent, W, Node}|Acc]).

words(Topic) when is_binary(Topic) ->
  [word(W) || W <- binary:split(Topic, <<"/">>, [global])].

word(<<>>)    -> '';
word(<<"+">>) -> '+';
word(<<"#">>) -> '#';
word(Bin)     -> Bin.
