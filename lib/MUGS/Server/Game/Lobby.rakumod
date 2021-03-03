# ABSTRACT: Simple server for game selection lobby

use MUGS::Core;
use MUGS::Server;


#| Server side of game selection lobby
class MUGS::Server::Game::Lobby is MUGS::Server::Game {
    method game-type() { 'lobby' }
    method game-desc() { 'Game selection lobby' }
}


# Register this class as a valid server class
MUGS::Server::Game::Lobby.register;
