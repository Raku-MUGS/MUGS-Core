# ABSTRACT: Echo client for testing MUGS itself

use MUGS::Core;
use MUGS::Client::Genre::Test;


#| Client side of echo test
class MUGS::Client::Game::Echo is MUGS::Client::Genre::Test {
    method game-type() { 'echo' }

    method send-echo-message($message, &on-success?) {
        self.action-promise: hash(:type<echo>, :$message), &on-success;
    }
}


# Register this class as a valid client
MUGS::Client::Game::Echo.register;
