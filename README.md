# match_trie

[![CI](https://github.com/barrel-db/match_trie/actions/workflows/ci.yml/badge.svg)](https://github.com/barrel-db/match_trie/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/match_trie.svg)](https://hex.pm/packages/match_trie)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/match_trie)

An Erlang trie (prefix tree) implementation using ETS for efficient MQTT-style topic matching with wildcard support.

## Features

- Fast topic matching using ETS ordered sets
- MQTT-style wildcard support (`+` and `#`)
- System topic protection (`$SYS/...`)
- Concurrent read access
- Topic validation

## Installation

Add `match_trie` to your `rebar.config` dependencies:

```erlang
{deps, [
    {match_trie, "0.1.0"}
]}.
```

## Quick Start

```erlang
%% Create a new trie
Trie = match_trie:new(),

%% Insert topic patterns
ok = match_trie:insert(Trie, <<"sensors/+/temperature">>),
ok = match_trie:insert(Trie, <<"sensors/#">>),
ok = match_trie:insert(Trie, <<"alerts/critical">>),

%% Find matching patterns for a topic
Matches = match_trie:match(Trie, <<"sensors/room1/temperature">>),
%% Returns: [<<"sensors/+/temperature">>, <<"sensors/#">>]

%% Delete a pattern
ok = match_trie:delete(Trie, <<"sensors/#">>),

%% Clean up when done
ok = match_trie:delete(Trie).
```

## Wildcards

Two wildcards are supported following MQTT conventions:

**`+` (single-level):** Matches exactly one topic segment.

```erlang
%% "sensors/+/temperature" matches:
%%   - "sensors/room1/temperature"
%%   - "sensors/kitchen/temperature"
%% Does NOT match:
%%   - "sensors/floor1/room1/temperature"
```

**`#` (multi-level):** Matches zero or more segments. Must be the last segment.

```erlang
%% "sensors/#" matches:
%%   - "sensors"
%%   - "sensors/temperature"
%%   - "sensors/room1/temperature"
```

## System Topics

Topics starting with `$` (like `$SYS/...`) are not matched by `+` or `#` wildcards at the root level:

```erlang
false = match_trie:is_match(<<"$SYS/broker/clients">>, <<"#">>),
false = match_trie:is_match(<<"$SYS/broker/clients">>, <<"+/broker/clients">>),
true = match_trie:is_match(<<"$SYS/broker/clients">>, <<"$SYS/#">>).
```

## API

| Function | Description |
|----------|-------------|
| `new/0`, `new/1` | Create a new trie (with optional ETS access mode) |
| `insert/2` | Insert a topic pattern |
| `match/2` | Find all patterns matching a topic |
| `delete/1` | Delete the entire trie |
| `delete/2` | Remove a pattern from the trie |
| `validate/1` | Validate a topic name or filter |
| `is_match/2` | Check if a topic matches a filter |
| `is_wildcard/1` | Check if a topic contains wildcards |

## Concurrency

The trie uses ETS tables internally. By default, tables are created with `protected` access, allowing concurrent reads from any process while writes are restricted to the owner.

```erlang
%% Private: only owner can read/write
Trie1 = match_trie:new(private),

%% Protected (default): any process can read, owner writes
Trie2 = match_trie:new(protected),

%% Public: any process can read/write
Trie3 = match_trie:new(public).
```

## License

This project is licensed under the Mozilla Public License 2.0. See [LICENSE](LICENSE) for details.
