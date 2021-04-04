# ABSTRACT: Game selection lobby

use MUGS::Core;
use MUGS::Client;


#| Client side of game selection lobby
class MUGS::Client::Game::Lobby is MUGS::Client::Game {
    method game-type() { 'lobby' }

    method filter-client-exists(@games) {
        @games.grep: { MUGS::Client.implementation-exists(.<game-type>) }
    }

    method extract-games($game-list, Bool :$all) {
        with $game-list {
            my @filtered = $all ?? @$_ !! self.filter-client-exists($_)
        }
        else { Empty }
    }

    method available-game-types(Bool :$all) {
        my $data = await $.session.get-info-bundle([ <available-game-types >]);
        self.extract-games($data<available-game-types>, :$all)
    }

    method active-games(Bool :$all) {
        my $data = await $.session.get-info-bundle([ <active-games >]);
        self.extract-games($data<active-games>, :$all)
    }
}


# Register this class as a valid client
MUGS::Client::Game::Lobby.register;
