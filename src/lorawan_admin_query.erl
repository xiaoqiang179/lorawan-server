% Bounded selection for administration pages. Only the requested best records
% are retained; large payloads are never converted or sorted as a full list.
-module(lorawan_admin_query).
-export([top/5]).

top(Table, MatchSpec, Position, Direction, Limit) ->
    mnesia:activity(async_dirty, fun() ->
        collect(mnesia:select(Table, MatchSpec, 128, read),
            Position, Direction, Limit, 0, gb_trees:empty())
    end).

collect('$end_of_table', _Position, Direction, _Limit, Count, Tree) ->
    Values = gb_trees:values(Tree),
    {Count, case Direction of asc -> Values; desc -> lists:reverse(Values) end};
collect({Records, Continuation}, Position, Direction, Limit, Count, Tree) ->
    Next = lists:foldl(fun(Record, Acc) ->
        retain(Record, Position, Direction, Limit, Acc)
    end, Tree, Records),
    collect(mnesia:select(Continuation), Position, Direction, Limit,
        Count + length(Records), Next).

retain(Record, Position, Direction, Limit, Tree) ->
    Value = case element(Position, Record) of
        undefined -> {0, undefined};
        null -> {0, undefined};
        Defined -> {1, Defined}
    end,
    Key = {Value, element(2, Record)},
    Updated = gb_trees:enter(Key, Record, Tree),
    case gb_trees:size(Updated) > Limit of
        false -> Updated;
        true when Direction == asc ->
            {_, _, Rest} = gb_trees:take_largest(Updated), Rest;
        true ->
            {_, _, Rest} = gb_trees:take_smallest(Updated), Rest
    end.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

retain_test() ->
    Records = [{row, <<N:32>>, N rem 23} || N <- lists:seq(1, 1000)],
    lists:foreach(fun(Direction) ->
        Tree = lists:foldl(fun(R, T) -> retain(R, 3, Direction, 7, T) end,
            gb_trees:empty(), Records),
        Expected = lists:sort(fun(A, B) ->
            {element(3, A), element(2, A)} < {element(3, B), element(2, B)}
        end, Records),
        Ordered = case Direction of asc -> Expected; desc -> lists:reverse(Expected) end,
        Actual = case Direction of
            asc -> gb_trees:values(Tree);
            desc -> lists:reverse(gb_trees:values(Tree))
        end,
        ?assertEqual(lists:sublist(Ordered, 7), Actual),
        ?assertEqual(7, gb_trees:size(Tree))
    end, [asc, desc]).

null_order_test() ->
    Records = [{row, a, undefined}, {row, b, 0}, {row, c, 2}],
    Asc = lists:foldl(fun(R, T) -> retain(R, 3, asc, 2, T) end,
        gb_trees:empty(), Records),
    Desc = lists:foldl(fun(R, T) -> retain(R, 3, desc, 2, T) end,
        gb_trees:empty(), Records),
    ?assertEqual([a, b], [element(2, R) || R <- gb_trees:values(Asc)]),
    ?assertEqual([b, c], [element(2, R) || R <- gb_trees:values(Desc)]).
top_test_() ->
    {setup,
        fun() ->
            {ok, _} = application:ensure_all_started(mnesia),
            {atomic, ok} = mnesia:create_table(admin_query_test,
                [{attributes, [id, value]}]),
            lists:foreach(fun(N) ->
                mnesia:dirty_write({admin_query_test, N, N rem 23})
            end, lists:seq(1, 10000))
        end,
        fun(_) -> mnesia:delete_table(admin_query_test) end,
        fun(_) -> [
            ?_assertEqual({10000, [{admin_query_test, N, 22} || N <-
                lists:sublist(lists:reverse([X || X <- lists:seq(1, 10000), X rem 23 == 22]), 7)]},
                top(admin_query_test, [{{admin_query_test, '_', '_'}, [], ['$_']}], 3, desc, 7)),
            ?_assertEqual({0, []}, top(admin_query_test,
                [{{admin_query_test, '_', 99}, [], ['$_']}], 3, asc, 7)),
            ?_assertEqual({length([N || N <- lists:seq(1, 10000), N rem 23 == 0]),
                [{admin_query_test, N, 0} || N <- lists:seq(23, 23*14, 23)]},
                top(admin_query_test, [{{admin_query_test, '_', 0}, [], ['$_']}], 3, asc, 14))
        ] end}.
-endif.
