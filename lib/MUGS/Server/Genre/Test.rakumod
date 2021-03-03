# ABSTRACT: General server for test "games"

use MUGS::Core;
use MUGS::Server;


#| Server side of test "games"
class MUGS::Server::Genre::Test is MUGS::Server::Game {
    # method valid-action-types() { < nop foo > }

    # method ensure-action-valid($action) {
    #     callsame;

    #     if $action<type> eq 'foo' {
    #     }
    # }

    # method process-action-foo(::?CLASS:D: MUGS::Character:D :$character!, :$action!) {
    # }

    # method game-status(::?CLASS:D: $action-result) {
    #     hash(|callsame)
    # }
}
