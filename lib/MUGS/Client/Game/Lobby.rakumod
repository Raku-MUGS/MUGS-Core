# ABSTRACT: Game selection lobby

use MUGS::Core;
use MUGS::Client;


#| Client side of game selection lobby
class MUGS::Client::Game::Lobby is MUGS::Client::Game {
    method game-type() { 'lobby' }

    method available-game-types() {
        my $data = await $.session.get-info-bundle([ <available-game-types >]);
        with $data<available-game-types> {
            my @available = .grep: { MUGS::Client.implementation-exists(.<game-type>) };
        }
        else { Empty }
    }
}


# Register this class as a valid client
MUGS::Client::Game::Lobby.register;
