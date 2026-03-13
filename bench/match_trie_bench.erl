%% Copyright (c) 2016-2026 Benoit Chesneau
%%
%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at http://mozilla.org/MPL/2.0/.

-module(match_trie_bench).

-export([run/0, run/1]).
-export([bench_insert/2, bench_match/2, bench_delete/2]).

-define(DEFAULT_ITERATIONS, 10000).

%% @doc Run all benchmarks with default iterations.
run() ->
    run(?DEFAULT_ITERATIONS).

%% @doc Run all benchmarks with specified iterations.
run(N) ->
    io:format("~n=== match_trie benchmark ===~n"),
    io:format("Iterations: ~p~n~n", [N]),

    %% Generate test data
    Topics = generate_topics(N),
    Filters = generate_filters(N div 10),

    %% Run benchmarks
    io:format("--- Insert ---~n"),
    {InsertTime, Trie} = bench_insert(Topics, N),
    io:format("  Total: ~.2f ms~n", [InsertTime / 1000]),
    io:format("  Per op: ~.2f us~n", [InsertTime / N]),
    io:format("  Ops/sec: ~B~n~n", [round(N / (InsertTime / 1000000))]),

    io:format("--- Match (exact topics) ---~n"),
    {MatchTime, _} = bench_match(Trie, Topics),
    io:format("  Total: ~.2f ms~n", [MatchTime / 1000]),
    io:format("  Per op: ~.2f us~n", [MatchTime / N]),
    io:format("  Ops/sec: ~B~n~n", [round(N / (MatchTime / 1000000))]),

    io:format("--- Match (with wildcards) ---~n"),
    MatchTopics = [T || {T, _} <- lists:sublist(Topics, N div 10)],
    {WildcardTime, _} = bench_match_wildcard(Trie, MatchTopics, Filters),
    WildcardN = length(MatchTopics),
    io:format("  Total: ~.2f ms~n", [WildcardTime / 1000]),
    io:format("  Per op: ~.2f us~n", [WildcardTime / WildcardN]),
    io:format("  Ops/sec: ~B~n~n", [round(WildcardN / (WildcardTime / 1000000))]),

    io:format("--- Delete ---~n"),
    {DeleteTime, _} = bench_delete(Trie, Topics),
    io:format("  Total: ~.2f ms~n", [DeleteTime / 1000]),
    io:format("  Per op: ~.2f us~n", [DeleteTime / N]),
    io:format("  Ops/sec: ~B~n~n", [round(N / (DeleteTime / 1000000))]),

    match_trie:delete(Trie),
    ok.

%% @doc Benchmark insert operations.
bench_insert(Topics, _N) ->
    Trie = match_trie:new(),
    Time = measure(fun() ->
        lists:foreach(fun({Topic, _}) ->
            match_trie:insert(Trie, Topic)
        end, Topics)
    end),
    {Time, Trie}.

%% @doc Benchmark match operations.
bench_match(Trie, Topics) ->
    Time = measure(fun() ->
        lists:foreach(fun({Topic, _}) ->
            match_trie:match(Trie, Topic)
        end, Topics)
    end),
    {Time, ok}.

%% @doc Benchmark match with wildcard filters.
bench_match_wildcard(Trie, Topics, Filters) ->
    %% Insert wildcard filters
    lists:foreach(fun(Filter) ->
        match_trie:insert(Trie, Filter)
    end, Filters),

    Time = measure(fun() ->
        lists:foreach(fun(Topic) ->
            match_trie:match(Trie, Topic)
        end, Topics)
    end),
    {Time, ok}.

%% @doc Benchmark delete operations.
bench_delete(Trie, Topics) ->
    Time = measure(fun() ->
        lists:foreach(fun({Topic, _}) ->
            match_trie:delete(Trie, Topic)
        end, Topics)
    end),
    {Time, ok}.

%% Internal functions

measure(Fun) ->
    {Time, _} = timer:tc(Fun),
    Time.

generate_topics(N) ->
    [{generate_topic(I), I} || I <- lists:seq(1, N)].

generate_topic(I) ->
    Depth = (I rem 5) + 1,
    Segments = [segment(I, D) || D <- lists:seq(1, Depth)],
    iolist_to_binary(lists:join(<<"/">>, Segments)).

segment(I, D) ->
    Base = case D of
        1 -> [<<"sensors">>, <<"devices">>, <<"home">>, <<"office">>, <<"factory">>];
        2 -> [<<"temperature">>, <<"humidity">>, <<"pressure">>, <<"light">>, <<"motion">>];
        3 -> [<<"room">>, <<"floor">>, <<"zone">>, <<"area">>, <<"section">>];
        4 -> [<<"north">>, <<"south">>, <<"east">>, <<"west">>, <<"center">>];
        5 -> [<<"raw">>, <<"avg">>, <<"min">>, <<"max">>, <<"status">>]
    end,
    lists:nth((I rem 5) + 1, Base).

generate_filters(N) ->
    Patterns = [
        <<"sensors/+/room/#">>,
        <<"devices/#">>,
        <<"home/+/+/status">>,
        <<"+/temperature/#">>,
        <<"factory/+/zone/+/raw">>,
        <<"#">>,
        <<"+/+/+">>,
        <<"sensors/temperature/+">>,
        <<"office/#">>,
        <<"+/humidity/floor/#">>
    ],
    lists:sublist(lists:flatten(lists:duplicate((N div 10) + 1, Patterns)), N).
