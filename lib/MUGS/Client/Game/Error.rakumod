# ABSTRACT: Simple client for testing MUGS error paths

use MUGS::Core;
use MUGS::Client::Genre::Test;


#| Client side of error testing "game"
class MUGS::Client::Game::Error is MUGS::Client::Genre::Test {
    method game-type() { 'error' }

    method send-non-request-via-connection() {
        $.session.connection.send-to-server('NOT A REQUEST');
    }

    method send-non-request-via-session() {
        $.session.send-request('NOT A REQUEST');
    }

    method send-unknown-action-type(&on-success?) {
        self.action-promise: hash(:type<DoEsNoTeXiSt>), &on-success;
    }

    method send-missing-error-type(&on-success?) {
        self.action-promise: hash(:type<error>), &on-success;
    }

    method send-error-request($error, &on-success?) {
        self.action-promise: hash(:type<error>, :$error), &on-success;
    }
}


# Register this class as a valid client
MUGS::Client::Game::Error.register;
