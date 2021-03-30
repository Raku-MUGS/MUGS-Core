# ABSTRACT: Simple client for testing MUGS error paths

use MUGS::Core;
use MUGS::Client::Genre::Test;


#| Client side of error testing "game"
class MUGS::Client::Game::Error is MUGS::Client::Genre::Test {
    method game-type() { 'error' }

    method send-error-request($error, &on-success?) {
        self.action-promise: hash(:type<error>, :$error), &on-success;
    }
}


# Register this class as a valid client
MUGS::Client::Game::Error.register;
