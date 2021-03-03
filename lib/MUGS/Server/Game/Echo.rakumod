# ABSTRACT: Simple server for echo test

use MUGS::Core;
use MUGS::Server::Genre::Test;


#| Server side of echo test "game"
class MUGS::Server::Game::Echo is MUGS::Server::Genre::Test {
    method game-type() { 'echo' }
    method game-desc() { 'Test "game" that simply echoes input' }

    method valid-action-types() { < nop echo > }

    method ensure-action-valid(::?CLASS:D: MUGS::Character:D :$character!, :$action!) {
        callsame;

        X::MUGS::Request::AdHoc.new(message => "Message missing").throw
            if $action<type> eq 'echo' && !$action<message>.defined;
    }

    method process-action-echo(::?CLASS:D: MUGS::Character:D :$character!, :$action!) {
        hash(:echo($action<message>))
    }
}


# Register this class as a valid server class
MUGS::Server::Game::Echo.register;
