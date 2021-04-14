# ABSTRACT: Client-side abstract game logic and session handling

use MUGS::Core;
use MUGS::Message;
use MUGS::Connection;
use MUGS::Util::ImplementationRegistry;
use MUGS::Util::StructureValidator;

use Pluggable;

class MUGS::Client          { ... }
class MUGS::Client::Session { ... }


#| Client-side exceptions
class X::MUGS::Client is X::MUGS { }

#| Client-side internal errors
class X::MUGS::Client::Internal is X::MUGS::Client {
    has Str:D $.message is required;
}

#| Attempted operation requires a persona
class X::MUGS::Client::PersonaRequired is X::MUGS::Client {
    method message { "Must select a valid persona for this operation" }
}

#| Attempted operation requires a character
class X::MUGS::Client::CharacterRequired is X::MUGS::Client {
    method message { "Must select a valid character for this operation" }
}


#| Base class for a single character in a single game, as seen by the client
class MUGS::Client::Game {
    has MUGS::Client::Session:D $.session        is required;
    has GameID:D                $.game-id        is required;
    has Str:D                   $.character-name is required;
    has                         %.initial-state  is required;
    has                         &.on-push        is rw;
    has GameState               $.gamestate;


    # MUST be implemented in leaf game classes
    method game-type() { ... }

    # SHOULD be extended in genre or leaf game classes
    method canonify-initial-state() {
        self.fix-standard-enum-fields(%.initial-state);
    }

    # SHOULD be extended in genre or leaf game classes
    method canonify-response($response) {
        self.fix-standard-enum-fields($response.data);
    }

    # SHOULD be extended in genre or leaf game classes
    method canonify-push-update($pushed) {
        self.fix-standard-enum-fields($pushed.data);
    }

    method fix-standard-enum-fields(%data) {
        with %data<gamestate> {
            %data<gamestate> = GameState::{$_} unless $_ ~~ GameState;
            $!gamestate      = %data<gamestate>;
        }

        if %data<winloss> ~~ Map:D {
            for %data<winloss>.kv -> $identity, $winloss {
                %data<winloss>{$identity} = WinLoss::{$winloss}
                    unless $winloss ~~ WinLoss;
            }
        }
    }

    method my-winloss(::?CLASS:D: $response) {
        my %schema   = winloss => Map;
        my %winloss := $response.validated-data(%schema)<winloss>;
        my $winloss  = %winloss{$.character-name} // %winloss{''} // Undecided;
    }

    method flush-startup-messages(::?CLASS:D:) {
        $.session.flush-startup-messages(self);
    }

    method handle-server-message($message) {
        if $message.type eq 'game-update' {
            self.canonify-push-update($message);
        }

        $_($message) with &.on-push;
    }

    method register() {
        MUGS::Client.register-implementation(self.game-type, self.WHAT);
    }

    submethod TWEAK() {
        self.canonify-initial-state;
    }

    method leave(::?CLASS:D:) {
        $!session.leave-game(self);
    }

    method send-nop(::?CLASS:D: &on-success?) {
        self.action-promise: hash(:type<nop>), &on-success;
    }

    method action-promise($action, &on-success?) {
        my $response-promise = Promise.new;
        $!session.send-in-game-request:
            'action', self, $action,
            on-failure => $response-promise,
            on-success => -> $response {
                self.canonify-response($response);
                $_($response) with &on-success;
                $response-promise.keep($response);
            };

        $response-promise
    }

    # Used when Promise wrapper not needed, or custom on-success used
    method send-action(::?CLASS:D: $action, :&on-success, :$on-failure) {
        $!session.send-in-game-request('action', self, $action,
                                       :&on-success, :$on-failure);
    }

    method send-message-to-character(::?CLASS:D: &on-success?, Str:D :$character,
                                     Str:D :$message) {
        my %message := hash(:message-type<direct-message>, :$message,
                            :target-type<character>, :target($character),
                            :sender($.character-name), :sender-game($.game-id));
        self.message-promise: %message, &on-success;
    }

    method broadcast-message-to-game(::?CLASS:D: &on-success?, Str:D :$message) {
        my %message := hash(:message-type<broadcast>, :$message,
                            :target-type<game>, :target($.game-id),
                            :sender($.character-name), :sender-game($.game-id));
        self.message-promise: %message, &on-success;
    }

    method message-promise($message, &on-success?) {
        my $response-promise = Promise.new;
        $!session.send-in-game-request:
            'send-message', self, $message,
            on-failure => $response-promise,
            on-success => -> $response {
                $_($response) with &on-success;
                $response-promise.keep($response);
            };

        $response-promise
    }
}


#| Load and track available game clients
class MUGS::Client
 does Pluggable
 does MUGS::Util::ImplementationRegistry[MUGS::Client::Game] {
    method load-game-plugins() {
        my regex top-level-game { ^ 'MUGS::Client::Game::' \w+ $ }
        my @plugins = self.plugins(:plugins-namespace('Game'),
                                   :name-matcher(&top-level-game));
    }
}


#| A single session, as seen by the client
class MUGS::Client::Session {
    has Any:D                      $.server            is required;
    has MUGS::Client::Connection:D $.connection        is required;
    has Str                        $.username;
    has Str                        $.default-persona   is rw;
    has Str                        $.default-character is rw;
    has MUGS::Client::Game:D       %.games;
    has MUGS::Message::Request:D   %.pending;
    has                            %.startup;

    #| Check if a game client is active in this session
    method client-is-active(MUGS::Client::Game:D $client) {
        $client ∈ %.games.values
    }

    #| Connect to a server, init a user session, and listen for incoming messages
    method connect(::?CLASS:U: MUGS::Client::Connection :$connector!,
                   :$server!, *%connect-options) {
        # Make raw connection to server
        my $connection = $connector // $connector.new;
        $connection.connect-to-server(:$server, |%connect-options);

        # Initialize session with connection
        my $session = self.bless(:$server, :$connection);

        # Start listening to server in another thread
        start react whenever $connection.from-server-supply -> $message {
            $session.handle-server-message($message)
        }

        $session
    }

    #| Leave joined games, disconnect from server, clear pending requests
    method disconnect(::?CLASS:D:) {
        .leave for %.games.values;
        $!connection.disconnect;
        %!pending = ();
    }

    #| Destroyed by GC instead of disconnected by direct action
    submethod DESTROY() {
        # If DESTROY is called, the last *outside* reference to this session
        # and the MUGS::Client::Game objects bidirectionally linked from
        # %.games.values has disappeared.  However, there is no easy way to know
        # in what order the session and game objects will actually be destroyed,
        # so it is not safe to ask the game objects to leave the session the
        # way method .disconnect does, or in fact to refer to the game objects
        # directly at all.  Instead just try to tell the server we're leaving
        # these games using the *keys* of %.games (the GameIDs), ignoring any
        # failures along the way (we're being DESTROYed and shouldn't try to do
        # advanced recovery; the server has to know how to handle unexpected
        # client disconnection anyway) and then disconnect from the server.

        try self.leave-game(:game-id($_)) for %!games.keys;
        $!connection.disconnect;
        %!pending = ();
    }

    #| Handle messages that must be responses to client requests
    multi method handle-server-message(MUGS::Message::Response:D $response) {
        my $request-id = $response.request-id;
        my $request    = %!pending{$request-id}:delete
            or X::MUGS::Response::NoMatchingRequest.new(:$request-id).throw;

        if $response.status == Success {
            # XXXX: What if on-success throws an exception?
            $_($response) with $request.on-success;
        }
        else {
            # Clarity over performance -- this is a client-side error path,
            # rate-limited by the client's own request rate because of the
            # NoMatchingRequest check above.  No need to enable rapid-fire
            # footgunning.
            my $exception = do given $response.status {
                when ResponseError {
                    X::MUGS::Message::Undecodable.new
                }
                when ServerError {
                    X::MUGS::Response::ServerError.new(:error($response.data<error>))
                }
                when RequestError {
                    X::MUGS::Response::InvalidRequest.new(:$request, :error($response.data<error>))
                }
                default {
                    X::MUGS::Response::UnknownStatus.new(:status($_))
                }
            }

            with $request.on-failure {
                when Promise {
                    .break($exception)
                }
                when Callable {
                    $_($response, $exception)
                }
                default {
                    X::MUGS::Client::Internal.new(:message("Don't know how to handle on-failure of type { .^name }")).throw;
                }
            }
            else {
                $exception.throw;
            }
        }
    }

    #| Handle server-push messages
    multi method handle-server-message(MUGS::Message::Push:D $message) {
        with $message.data<game-id> {
            with   %!games{$_}   { .handle-server-message($message) }
            orwith %!startup{$_} { .push($message) }
            else { X::MUGS::Message::InvalidEntity.new(:type<game>, :id($_)).throw }
        }
        else {
            !!! "Don't yet know how to handle non-game push messages"
        }
    }

    method !response-promise($request-type, %data, &on-success) {
        my $promise = Promise.new;
        self.send-out-of-game-request($request-type, %data, on-failure => $promise,
                                      on-success => { $promise.keep(on-success($_)) });
        $promise
    }

    method !in-game-response-promise($type, $game, %data, &on-success) {
        my $promise = Promise.new;
        self.send-in-game-request($type, $game, %data, on-failure => $promise,
                                  on-success => { $promise.keep(on-success($_)) });
        $promise
    }

    method create-account-owner(::?CLASS:D: Str:D :$username!, Str:D :$password!
                                                                     --> Promise:D) {
        my %data := hash(:$username, :$password, :method<plaintext-password>);
        self!response-promise('create-account-owner', %data, { $!username = $username });
    }

    method authenticate(::?CLASS:D: Str:D :$username!, Str:D :$password! --> Promise:D) {
        my %data := hash(:$username, :$password, :method<plaintext-password>);
        self!response-promise('authenticate', %data, { $!username = $username });
    }

    method get-info-bundle(::?CLASS:D: @info-types --> Promise:D) {
        constant $available-identities =
        [
            {
                persona    =>   Str,
                characters => [ Str ]
            },
        ];
        constant $available-game-types =
        [
            {
                game-type    => Str,
                game-desc    => Str,
                genre-tags   => [ Str ],
                content-tags => [ Str ],
                config-form  => [
                                 {
                                     field           => Str,
                                     section         => Str,
                                     desc            => Str,
                                     type            => Str,
                                     default         => Any,
                                     visible-locally => Bool but Optional,
                                 }
                                ]
            }
        ];
        constant $active-games =
        [
            {
                game-id          => GameID,
                game-type        => Str,
                gamestate        => Str,
                config           => Map,
                num-participants => Int,
                created-by-me    => Bool,
                my-characters    => [ Str ],
            },
        ];
        constant %full-schema = :$available-identities,
                                :$available-game-types,
                                :$active-games;

        my %schema = @info-types.map({ $_ => %full-schema{$_} });
        my %data  := hash(:info-types(@info-types.join(' ')));
        self!response-promise('get-info-bundle', %data, *.validated-data(%schema));
    }

    method create-persona(::?CLASS:D: Str:D :$screen-name) {
        my %data := hash(:$screen-name);
        self!response-promise('create-persona', %data,
                              { $!default-persona   = $screen-name;
                                $!default-character = Str; });
    }

    method create-character(::?CLASS:D: Str:D :$screen-name, Str:D :$persona-name) {
        my %data := hash(:$screen-name, :$persona-name);
        self!response-promise('create-character', %data,
                              { $!default-persona   = $persona-name;
                                $!default-character = $screen-name; });
    }

    method new-game(::?CLASS:D: Str:D :$game-type where { MUGS::Client.implementation-exists($_) },
                    Str:D :$creator-persona-name = $!default-persona,
                    :%config --> Promise:D) {
        X::MUGS::Client::PersonaRequired.new.throw unless $creator-persona-name;

        my sub on-success($response) {
            constant %schema = game-id => GameID;
            my $game-id = $response.validated-data(%schema)<game-id>;
            %.startup{$game-id} //= [];
            $game-id
        }

        my %data := hash(:$game-type, :%config, :$creator-persona-name);
        self!response-promise('new-game', %data, &on-success);
    }

    method join-game(::?CLASS:D: Str:D :$game-type where { MUGS::Client.implementation-exists($_) },
                     GameID:D :$game-id, Str:D :$character-name = $!default-character
                     --> Promise:D) {
        X::MUGS::Client::CharacterRequired.new.throw unless $character-name;

        my sub on-success($response) {
            constant %schema  = initial-state => Map;
            my $initial-state = $response.validated-data(%schema)<initial-state>;
            my $class  = MUGS::Client.implementation-class($game-type);
            my $client = $class.new(:$game-id, :session(self),
                                    :$character-name, :$initial-state);
            %!games{$game-id} = $client;
        }

        %.startup{$game-id} //= [];
        my %data := hash(:$game-type, :$game-id, :$character-name);
        self!response-promise('join-game', %data, &on-success);
    }

    method flush-startup-messages(::?CLASS:D: MUGS::Client::Game:D $game) {
        my $game-id = $game.game-id;
        %!games{$game-id}.handle-server-message($_) for @(%!startup{$game-id});
        %!startup{$game-id}:delete;
    }

    multi method leave-game(::?CLASS:D: MUGS::Client::Game:D $game --> Promise:D) {
        self!in-game-response-promise('leave-game', $game, {},
                                      { %!games{$game.game-id}:delete })
    }

    #| Used in DESTROY, so avoids touching Game objects or awaiting response
    multi method leave-game(::?CLASS:D: GameID:D :$game-id,
                            Str :$character-name = $!default-character) {
        self.send-in-game-request(:type<leave-game>, :$game-id, :$character-name);
        %!games{$game-id}:delete;
    }

    multi method send-in-game-request(::?CLASS:D: Str:D $type,
                                      MUGS::Client::Game:D $game,
                                      %data, :&on-success, :$on-failure) {
        my $game-id        = $game.game-id;
        my $character-name = $game.character-name;

        my $request = MUGS::Message::Request::InGame.new(:$type, :$game-id,
                                                         :$character-name, :%data,
                                                         :&on-success, :$on-failure);
        self.send-request($request);
    }

    multi method send-in-game-request(::?CLASS:D: Str:D :$type!, GameID:D :$game-id!,
                                      Str:D :$character-name!, :%data,
                                      :&on-success, :$on-failure) {
        my $request = MUGS::Message::Request::InGame.new(:$type, :$game-id,
                                                         :$character-name, :%data,
                                                         :&on-success, :$on-failure);
        self.send-request($request);
    }

    method send-out-of-game-request(::?CLASS:D: Str:D $type, %data,
                                    :&on-success, :$on-failure) {
        my $request = MUGS::Message::Request.new(:$type, :%data,
                                                 :&on-success, :$on-failure);
        self.send-request($request);
    }

    method send-request(::?CLASS:D: MUGS::Message::Request:D $request) {
        %!pending{$request.id} = $request;
        $!connection.send-to-server($request);
    }
}
