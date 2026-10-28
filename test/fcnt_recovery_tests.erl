-module(fcnt_recovery_tests).
-include_lib("eunit/include/eunit.hrl").
-include("lorawan.hrl").
-include("lorawan_db.hrl").

-define(ADDR, <<16#12345678:32>>).
-define(KEY, <<16#2B7E151628AED2A6ABF7158809CF4F3C:128>>).
-define(DATA, <<1, 2, 3, 4>>).

fcnt_recovery_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun({Base, _Saved}) ->
        {inorder, [
            ?_test(begin
                set_node(Base, 7, 0),
                {uplink, {_, _, Recovered}, Frame} = ingest(500000),
                ?assertEqual(500000, Recovered#node.fcntup),
                ?assertEqual(?DATA, Frame#frame.data),
                ?assertEqual(500000, Frame#frame.fcnt),
                ?assertEqual(17, Recovered#node.fcntdown),
                ?assertEqual(Base#node.last_reset, Recovered#node.last_reset),
                with_attempts(0, fun() ->
                    ?assertMatch({uplink, _, #frame{data=?DATA}}, ingest(500001))
                end)
            end),
            ?_test(begin
                set_node(Base, 65535, 1),
                with_attempts(0, fun() ->
                    ?assertMatch({uplink, _, #frame{fcnt=65536}}, ingest(65536))
                end),
                ?assertMatch({retransmit, _, _}, ingest(65536)),
                ?assertEqual(65536, (load_node())#node.fcntup)
            end),
            ?_test(begin
                set_node(Base, 65541, 1),
                ?assertMatch({retransmit, _, #frame{fcnt=65541}}, ingest(65541))
            end),
            ?_test(begin
                set_node(Base, 0, 0),
                ?assertMatch({uplink, _, _}, ingest((99 bsl 16) bor 13)),
                set_node(Base, 0, 0),
                ?assertEqual({error, {node, ?ADDR}, bad_mic}, ingest((100 bsl 16) bor 13)),
                ?assertEqual(0, (load_node())#node.fcntup)
            end),
            ?_test(begin
                set_node(Base, 0, 0),
                with_attempts(1, fun() ->
                    ?assertEqual({error, {node, ?ADDR}, bad_mic}, ingest(65549))
                end),
                with_attempts(2, fun() ->
                    ?assertMatch({uplink, _, _}, ingest(65549))
                end)
            end),
            ?_test(begin
                set_node(Base, 0, 0),
                with_attempts(0, fun() ->
                    ?assertEqual({error, {node, ?ADDR}, bad_mic}, ingest(65549)),
                    ?assertMatch({uplink, _, _}, ingest(1))
                end)
            end),
            ?_test(begin
                set_node(Base, undefined, 1),
                ?assertMatch({uplink, _, #frame{fcnt=300000}}, ingest(300000))
            end),
            ?_test(begin
                set_node(Base, 500000, 1),
                ?assertMatch({ignore, _}, ingest(300000)),
                ?assertEqual(500000, (load_node())#node.fcntup)
            end),
            ?_test(begin
                set_node(Base, 100, 2),
                seed_queues(),
                ?assertEqual({error, {node, ?ADDR}, bad_mic},
                    lorawan_mac:ingest_frame(<<0:64>>, frame(3, <<0:128>>))),
                ?assertEqual(100, (load_node())#node.fcntup),
                ?assertEqual(17, (load_node())#node.fcntdown),
                ?assertMatch([_], mnesia:dirty_read(pending, ?ADDR)),
                ?assertMatch([_], mnesia:dirty_read(queued, <<"fcnt-test">>)),
                ?assertMatch({uplink, _, _}, ingest(3)),
                ?assertEqual(0, (load_node())#node.fcntdown),
                ?assertEqual([], mnesia:dirty_read(pending, ?ADDR)),
                ?assertEqual([], mnesia:dirty_read(queued, <<"fcnt-test">>))
            end),
            ?_test(begin
                set_node(Base, 65535, 0),
                with_attempts(0, fun() -> ?assertMatch({uplink, _, _}, ingest(0)) end)
            end),
            ?_test(begin
                set_node(Base, 16#FFFFFFFF, 1),
                ?assertEqual({error, {node, ?ADDR}, bad_mic}, ingest(0)),
                ?assertEqual(16#FFFFFFFF, (load_node())#node.fcntup)
            end),
            ?_test(with_attempts(-1, fun() ->
                ?assertError({invalid_configuration, fcnt_recovery_attempts, -1},
                    lorawan_app:start(normal, []))
            end))
        ]}
    end}.

setup() ->
    {ok, _} = application:ensure_all_started(lorawan_server),
    Saved = application:get_env(lorawan_server, fcnt_recovery_attempts),
    application:set_env(lorawan_server, fcnt_recovery_attempts, 100),
    test_admin:add_network(<<"fcnt-net">>),
    test_admin:add_group(<<"fcnt-net">>, <<"fcnt-group">>),
    test_admin:add_profile(<<"fcnt-group">>, <<"fcnt-profile">>),
    test_admin:add_node(<<"fcnt-profile">>, {?ADDR,
        lorawan_utils:binary_to_hex(?KEY), lorawan_utils:binary_to_hex(?KEY)}),
    {load_node(), Saved}.

cleanup({_Base, Saved}) ->
    restore(Saved),
    application:stop(lorawan_server),
    application:stop(mnesia).

set_node(Base, Counter, Mode) ->
    [Profile] = mnesia:dirty_read(profile, Base#node.profile),
    mnesia:dirty_write(Profile#profile{fcnt_check=Mode}),
    mnesia:dirty_write(Base#node{fcntup=Counter, fcntdown=17}).
load_node() -> [Node] = mnesia:dirty_read(node, ?ADDR), Node.
ingest(Counter) -> lorawan_mac:ingest_frame(<<0:64>>, frame(Counter, ?KEY)).
frame(Counter, SigningKey) ->
    Encrypted = lorawan_utils:reverse(lorawan_mac:cipher(?DATA, ?KEY, 0, ?ADDR, Counter)),
    Msg = <<16#40, (lorawan_utils:reverse(?ADDR))/binary, 0,
        (Counter band 16#FFFF):16/little, 1, Encrypted/binary>>,
    MIC = crypto:cmac(aes_cbc128, SigningKey,
        <<(lorawan_mac:b0(0, ?ADDR, Counter, byte_size(Msg)))/binary, Msg/binary>>, 4),
    <<Msg/binary, MIC/binary>>.
seed_queues() ->
    mnesia:dirty_write(#pending{devaddr=?ADDR, confirmed=true}),
    mnesia:dirty_write(#queued{frid= <<"fcnt-test">>, devaddr=?ADDR}).
with_attempts(Count, Fun) ->
    Saved = application:get_env(lorawan_server, fcnt_recovery_attempts),
    application:set_env(lorawan_server, fcnt_recovery_attempts, Count),
    try Fun() after restore(Saved) end.
restore(undefined) -> application:unset_env(lorawan_server, fcnt_recovery_attempts);
restore({ok, Count}) -> application:set_env(lorawan_server, fcnt_recovery_attempts, Count).
