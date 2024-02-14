# ABSTRACT: Core routines for the Lobby pseudo-game

use MUGS::UI;


#| Core routines for the Lobby pseudo-game needed by all UI types
role MUGS::UI::Game::Lobby {
    ### Required methods
    method filter-games-for-ui { ... }

    #| Optionally filter Client's available game list for this UI type
    method available-game-types(::?CLASS:D: Bool :$all) {
        self.filter-games-for-ui($.client.available-game-types, :$all)
    }

    #| Optionally filter Client's active game list for this UI type
    method active-games(::?CLASS:D: Bool :$all) {
        self.filter-games-for-ui($.client.active-games, :$all)
    }
}
