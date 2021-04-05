# ABSTRACT: UI abstract logic

use MUGS::Core;
use MUGS::Client;
use MUGS::Util::ImplementationRegistry;

use Pluggable;


class MUGS::UI { ... }


#| Base class for a single game UI
class MUGS::UI::Game {
    has MUGS::Client::Game:D $.client is required;  #= Non-UI-specific client
    has $.app-ui;                                   #= Parent UI application

    # MUST be implemented by each base UI or leaf game class, respectively
    method ui-type()            { ... }
    method game-type()          { ... }
    method show-initial-state() { ... }

    # CAN be extended for UI- or game-specific details
    method initialize() { self.client.flush-startup-messages }  #= Game UI first launched
    method activate()               { }  #= Game UI activated/switched to
    method deactivate()             { }  #= Game UI backgrounded
    method shutdown()               { }  #= Game UI about to be torn down
    method handle-server-message($) { }  #= Called with each server-pushed message


    submethod TWEAK() {
        # Set up triggers and async callbacks from client layer
        self.client.on-push = { self.handle-server-message($_) };
    }

    method register() {
        MUGS::UI.register-ui(self.ui-type, self.game-type, self.WHAT);
    }
}


#| Load and track available game UIs
class MUGS::UI
 does Pluggable
 does MUGS::Util::UIRegistry[MUGS::UI::Game] {
    method load-game-plugins(Str:D $ui-type) {
        my regex top-level-game { ^ 'MUGS::UI::' $ui-type '::Game::' \w+ $ }
        my @plugins = self.plugins(:plugins-namespace($ui-type ~ '::Game'),
                                   :name-matcher(&top-level-game));
    }
}
