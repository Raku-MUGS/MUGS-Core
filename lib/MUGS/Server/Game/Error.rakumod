# ABSTRACT: Simple server for error testing "game"

use MUGS::Core;
use MUGS::Server::Genre::Test;


#| Server side of error testing "game"
class MUGS::Server::Game::Error is MUGS::Server::Genre::Test {
    method game-type() { 'error' }
    method game-desc() { 'Test "game" that throws different exceptions/errors on request' }

    method valid-action-types() { < nop error > }

    method ensure-action-valid(::?CLASS:D: MUGS::Character:D :$character!, :$action!) {
        callsame;

        X::MUGS::Request::AdHoc.new(message => "Message missing").throw
            if $action<type> eq 'error' && !$action<error>;
    }

    method process-action-error(::?CLASS:D: MUGS::Character:D :$character!, :$action!) {
        given $action<error> {
            when '' {
            }
            default {
                X::MUGS::Request::AdHoc.new(message => "Unrecognized error request").throw
            }
        }
        # hash(:echo($action<message>))
    }
}


# Register this class as a valid server class
MUGS::Server::Game::Error.register;
