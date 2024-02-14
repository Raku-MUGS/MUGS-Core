# ABSTRACT: Server-side abstract game logic and session handling

use MUGS::Core;
use MUGS::Message;
use MUGS::Connection;
use MUGS::Identity;
use MUGS::Util::ImplementationRegistry;
use MUGS::Util::StructureValidator;
use MUGS::Server::Storage::Identities;
use MUGS::Server::Storage::Credentials;
use MUGS::Server::LogTimelineSchema;

use Pluggable;


class MUGS::Server          { ... }
class MUGS::Server::Game    { ... }
class MUGS::Server::Session { ... }


#| Server-side exceptions
class X::MUGS::Server is X::MUGS { }

#| Character not in game
class X::MUGS::Server::CharacterNotInGame is X::MUGS::Server {
    has MUGS::Server::Game:D $.game      is required;
    has MUGS::Character:D    $.character is required;

    method message {
        "Character '$.character.screen-name()' not in game '$.game.id()'"
    }
}

#| Character already in game
class X::MUGS::Server::CharacterAlreadyInGame is X::MUGS::Server {
    has MUGS::Server::Game:D $.game      is required;
    has MUGS::Character:D    $.character is required;

    method message {
        "Character '$.character.screen-name()' already in game '$.game.id()'"
    }
}

#| Game ID and type do not match
class X::MUGS::Server::GameTypeMismatch is X::MUGS::Server {
    has GameID:D $.game-id   is required;
    has Str:D    $.game-type is required;

    method message {
        "Game '$.game-id' does not have type '$.game-type'"
    }
}

#| Game ID and type do not match
class X::MUGS::Server::InvalidNewGameConfig is X::MUGS::Server {
    has Str:D $.game-type is required;
    has Str:D $.reason    is required;
    has       $.config    is required;

    method message {
        "Invalid new game config for game type '$.game-type'"
        ~ (": $.reason" if $.reason)
    }
}

#| Invalid authentication credentials
class X::MUGS::Server::InvalidCredentials is X::MUGS::Server {
    has Str:D $.username is required;

    method message {
        "Invalid authenication credentials for user '$.username'"
    }
}


class MUGS::Server::GameEvent {
    has                 $.id         = NEXT-ID;
    has Instant:D       $.timestamp  = now;
    has Real:D          $.game-time  is required;
    has GameEventType:D $.event-type is required;
    has MUGS::User      $.user;
    has MUGS::Character $.character;
    has                 %.data;

    method to-struct(::?CLASS:D: --> Hash) {
        my $timestamp = $.timestamp.Rat;
        my $game-time = $.game-time.Rat;

        { :$.id, :$timestamp, :$game-time, :$.event-type, :%.data,
          |(:character-name($.character.screen-name) if $.character) }
    }
}


#| Base class for a single game running on the server
class MUGS::Server::Game {
    has                $.id        = NEXT-ID;
    has GameState:D    $.gamestate = NotStarted;
    has Instant:D      $.prev-time = now;
    has Real:D         $.game-time = 0.0;
    has Channel        $.input    .= new;
    has MUGS::Server:D $.server    is required;
    has MUGS::User:D   $.creator   is required;

    has Map:D                     %.participant;
    has WinLoss:D                 %.winloss;
    has                           %.config;
    has MUGS::Server::GameEvent:D @.events;


    # MUST be implemented in leaf game classes
    method game-type() { ... }
    method game-desc() { ... }


    # SHOULD be extended in genre or leaf game classes
    method genre-tags()   { Empty }
    method content-tags() { Empty }
    method wrap-character(::?CLASS:D: MUGS::Character:D $character) { }

    method config-form() {
        # XXXX: Eventually convert to a magic form class format, as with
        #       https://cro.services/docs/reference/cro-webapp-form

        # NOTE: Implicitly all of these have an additional :!visible-locally
        #       attribute, which should only be set True for fields that make
        #       sense for local in-memory solo play.

        # XXXX: Consider a locked attribute, for fields that can only be
        #       changed by server admins

        # XXXX: Validation failure reason
        [
            { field    => 'game-name',
              section  => 'General',
              desc     => 'Human-friendly name for this instance of the game',
              type     => Str,
              default  => '',
            },
            { field    => 'min-players',
              section  => 'Players',
              desc     => 'Minimum players to keep game open',
              type     => UInt,
              default  => 1,
            },
            { field    => 'start-players',
              section  => 'Players',
              desc     => 'Minimum players to start game',
              type     => UInt,
              default  => 1,
              validate => [ 'start-players >= min-players'
                            => { .<start-players> >= .<min-players> } ]
            },
            { field    => 'max-players',
              section  => 'Players',
              desc     => 'Maximum players simultaneously in game',
              type     => UInt,
              default  => 1,
              validate => [ 'max-players >= min-players and max-players >= start-players'
                            => { .<max-players> >= max(.<min-players>, .<start-players>) } ]
            },
            { field    => 'invites-only',
              section  => 'Players',
              desc     => 'Require an invite to join the game',
              type     => Bool,
              default  => False,
            },
            { field    => 'allow-invites',
              section  => 'Players',
              desc     => 'Allow players to invite others',
              type     => Bool,
              default  => True,
            },
            { field    => 'allow-joins-after-start',
              section  => 'Players',
              desc     => 'Allow players to join after game has started',
              type     => Bool,
              default  => True,
            },
        ]
    }


    # Most game implementations will NOT override these
    method register() {
        self.ensure-safe-to-register;

        MUGS::Server.register-implementation(self.game-type, self.WHAT);
    }

    method ensure-safe-to-register() {
        self.ensure-valid-config-form;
    }

    submethod BUILD(:$!server!, :$!creator!, :%config!) {
        self.ensure-valid-config(%config);
        %!config := %config;
    }

    submethod TWEAK() {
        self.update-time;

        my %data = :game-type(self.game-type), :game-id($!id);
        self.add-event(GameCreated, :user($!creator), :%data);
    }

    method change-config-default(:$form, Str:D :$field, :$default) {
        my $field-def = $form.first(*<field> eq $field)
            or die "No such config field '$field'";
        die "Proposed new default ({$default.raku}) for config field '$field' does not match config field type '{$field-def<type>.^name}'"
            unless $default ~~ $field-def<type>;
        $field-def<default> = $default;
    }

    method ensure-valid-config-form() {
        constant $schema = [
            {
                field    => Str:D,
                section  => Str:D,
                desc     => Str:D,
                type     => Any:U,
                default  => Any:D,
                # XXXX: Backwords compatibility with MUGS-Core 0.1.2 API
                validate => (Callable | [ Pair:D ]) but Optional,
                visible-locally => Bool but Optional,
            },
        ];
        validate-structure('config form', self.config-form, $schema);
    }

    method ensure-valid-config(%config) {
        my sub invalid-config($reason) {
            X::MUGS::Server::InvalidNewGameConfig.new(:$.game-type, :$reason, :%config).throw;
        }

        my %form = self.config-form.map: { .<field> => $_ };

        # Phase 1: Ensure all specified config values match the form constraints
        for %config.kv -> $k, $v {
            if %form{$k} -> %field-def {
                my $type = %field-def<type>;
                invalid-config("value for config field '$k' must have type { $type.^name }")
                    unless $v ~~ $type;
                if %field-def<validate> -> @validations {
                    for @validations -> $ (:key($reason), :value(&check)) {
                        invalid-config("value for config field '$k' does not pass validation '$reason'") unless check(%config);
                    }
                }
                # XXXX: Backwords compatibility with MUGS-Core 0.1.2 API
                elsif %field-def<validate> -> &check {
                    invalid-config("value for config field '$k' does not pass validation")
                        unless check(%config);
                }
            }
            else {
                invalid-config('unknown config field')
            }
        }

        # Phase 2: Set defaults for unspecified or undefined fields
        for %form.values -> %field-def {
            %config{%field-def<field>} //= %field-def<default>;
        }
    }

    method start-dispatcher(::?CLASS:D:) {
        start react whenever $!input -> $ (:key($session), :value($request)) {
            self.dispatch-request($session, $request);
        }
    }

    method enqueue-request(::?CLASS:D: MUGS::Server::Session:D $session,
                           MUGS::Message::Request:D $request) {
        $!input.send($session => $request);
    }

    method dispatch-request(::?CLASS:D: MUGS::Server::Session:D $session,
                            MUGS::Message::Request::InGame:D $request) {
        # Convert exceptions to response errors
        CATCH {
            $session.log-exception(:exception($_), :$request);

            when X::MUGS::Request { return $session.error(RequestError, .message, $request.id) }
            when X::MUGS::Message { return $session.error(RequestError, .message, $request.id) }
            default               { return $session.error(ServerError,  .message, $request.id) }
        }

        # Ensure this character exists, and grab the character object for later
        my $character-name = $request.character-name;
        my $character      = self.character-by-name($character-name);

        # Check that this character is in this game in this session
        X::MUGS::Message::InvalidEntity.new(:type<character>, :id($character-name)).throw
            unless $session === self.session-for-character($character);

        # XXXX: User must be allowed to use character (implied by above restrictions?)
        #       * Not implied if user's rights can change mid-session

        # Update game time info
        self.update-time;

        # Dispatch on request type, with most common types checked first
        # XXXX: Replace this with an old school dispatch table
        given $request.type {
            when 'action' {
                # XXXX: Need better error checking around .process-action call
                # XXXX: At least check that action<type> exists (and perhaps
                #       is a type known to the game class).  Better yet, check
                #       that the action matches the appropriate type for actions
                #       of that game class.
                my $result = self.process-action(:$character, :action($request.data));
                $session.success($result, $request.id);
            }
            when 'send-message' {
                constant %schema =
                    message => Str, message-type => Str, target-type => Str,
                    target => Any but Optional;

                my $data = $request.validated-data(%schema);
                my ($message, $message-type, $target-type)
                    = $data< message message-type target-type >;

                if $message-type eq 'broadcast' && $target-type eq 'game' {
                    my $target-id = $data<target>
                        orelse X::MUGS::Message::MissingData.new(:field<target>).throw;
                    X::MUGS::Message::InvalidEntity.new(:type<game-id>, :id($.id)).throw
                        unless $target-id == $.id;
                    self.broadcast-message-to-game(:sender($character), :$message);
                    $session.success({ :target($.id) }, $request.id);
                }
                elsif $message-type eq 'direct-message' && $target-type eq 'character' {
                    my $target-name = $data<target>
                        orelse X::MUGS::Message::MissingData.new(:field<target>).throw;
                    X::MUGS::Message::InvalidEntity.new(:type<character>, :id($target-name)).throw
                        unless $target-name ~~ Str;
                    self.send-to-character(:sender($character), :$target-name, :$message);
                    $session.success({ :target($target-name) }, $request.id);
                }
                else {
                    my $message = 'Invalid message-type or target-type in send-message request';
                    X::MUGS::Response::InvalidRequest(:$request, :$message).new.throw;
                }
            }
            when 'leave-game' {
                self.remove-character($character);
                $session.success({ :game-id($.id), :$character-name }, $request.id)
            }
            default {
                $session.error(RequestError, "Unknown in-game request type '$_'", $request.id)
            }
        }
    }

    #| Update game-time if currently in progress, and update prev-time regardless
    method update-time(::?CLASS:D:) {
        my $now      = now;
        $!game-time += $now - $!prev-time if $!gamestate == InProgress;
        $!prev-time  = $now;
    }

    method add-event(::?CLASS:D: GameEventType:D $event-type, *%extra) {
        my $event = MUGS::Server::GameEvent.new(:$event-type, :$!game-time,
                                                :timestamp($!prev-time), |%extra);
        dd $event if $*DEBUG;
        @!events.push($event);

        # GameCreated happens too early for clients to recognize the game;
        # otherwise broadcast GameEvents to all participants.
        unless $event-type == GameCreated {
            my $type  = 'game-event';
            my %data := hash(:game-id($.id), :event($event.to-struct));
            for self.participants -> (:character($c), :$session, :$instance) {
                $session.push(:$type, :%data);
            }
        }
    }

    method add-character-action-event(::?CLASS:D: MUGS::Character:D :$character!,
                                      :$action!) {
        self.add-event(CharacterAction, :$character, :data($action))
            unless $action<type> eq 'nop';
    }

    method set-gamestate(::?CLASS:D: GameState:D $new-state) {
        return if $!gamestate == $new-state;

        self.update-time;

        constant %state-event = Paused,     GamePaused,
                                InProgress, GameStarted,
                                Finished,   GameEnded,
                                Abandoned,  GameEnded;

        # XXXX: Setting event user and character?
        my %data = :old-state($!gamestate), :$new-state;
        self.add-event(%state-event{$new-state}, :%data);

        $!gamestate = $new-state;
    }

    method set-winloss(::?CLASS:D: WinLoss:D $new-winloss, MUGS::Identity $identity?) {
        self.update-time;

        %!winloss{$identity // ''} = $new-winloss;
        self.set-gamestate(Finished) if %!winloss{''};
    }

    method process-action(::?CLASS:D: MUGS::Character:D :$character!, :$action!) {
        self.ensure-action-valid(:$character, :$action);
        self.add-character-action-event(:$character, :$action);

        my $result = self."process-action-$action<type>"(:$character, :$action);
        self.post-process-action(:$character, :$action, :$result);
        self.game-status($result);
    }

    method ensure-action-valid(::?CLASS:D: MUGS::Character:D :$character!, :$action!) {
        X::MUGS::Request::MissingAction.new.throw unless $action<type>;
        X::MUGS::Request::InvalidAction.new.throw
            unless $action<type> ∈ self.valid-action-types;
    }

    method valid-action-types() {
        ('nop',)
    }

    method process-action-nop(::?CLASS:D: MUGS::Character:D :$character!, :$action!) {
        Empty
    }

    method post-process-action(::?CLASS:D: MUGS::Character:D :$character!,
                               :$action!, :$result!) {
        # Intentionally empty; just providing a hook
    }

    method initial-state(::?CLASS:D:) {
        self.game-status( () );
    }

    method game-status(::?CLASS:D: $action-result) {
        hash(:$.gamestate, :%.winloss, |$action-result);
    }

    method broadcast-update-to-game(::?CLASS:D: %update) {
        my %data := hash(:game-id($.id), |%update);
        my $pack  = MUGS::Message::DataPack.new(%data);

        .<session>.push-pack(:type<game-update>, :$pack) for self.participants;
    }

    method broadcast-message-to-game(::?CLASS:D: MUGS::Character:D :$sender!,
                                     Str:D :$message!) {
        my $game-id = $.id;
        for self.participants -> $p {
            $p<session>.push-message(:$game-id, :character($p<character>),
                                     :$message, :$sender, :message-type<broadcast>);
        }
    }

    method send-to-character(::?CLASS:D: MUGS::Character:D :$sender!,
                             Str:D :$target-name!, Str:D :$message!) {
        my $target         = self.character-by-name($target-name);
        my $target-session = self.session-for-character($target);
        $target-session.push-message(:game-id($!id), :character($target),
                                     :$message, :$sender,
                                     :message-type<direct-message>);
    }

    method ensure-character-in-game(::?CLASS:D: $character) {
        X::MUGS::Server::CharacterNotInGame.new(:$character, :game(self)).throw
            unless self.character-in-game($character);
    }

    method ensure-character-not-in-game(::?CLASS:D: $character) {
        X::MUGS::Server::CharacterAlreadyInGame.new(:$character, :game(self)).throw
            if self.character-in-game($character);
    }

    method ensure-game-not-full(::?CLASS:D:) {
        die "Game is full" if %.participant.elems == %.config<max-players>;
    }

    # This method exists to improve scalability and performance.  Since the
    # character object matching each client's request must be looked up on
    # every game action, fast paced games could easily overload the database
    # backing `Server.character-by-name`.  Instead, since each Game keeps an
    # in-memory cache of joined characters anyway, just pull from there, but
    # respect the original API that a failed character-name lookup must throw
    # an exception.
    method character-by-name(::?CLASS:D: Str:D $character-name) {
        %!participant{$character-name}<character>
            or X::MUGS::Message::InvalidEntity.new(:type('character'),
                                                   :id($character-name)).throw
    }

    method character-in-game(::?CLASS:D: MUGS::Character:D $character) {
        %!participant{$character.screen-name}:exists
    }

    method session-for-character(::?CLASS:D: MUGS::Character:D $character) {
        %!participant{$character.screen-name}<session>
    }

    method instance-for-character(::?CLASS:D: MUGS::Character:D $character) {
        %!participant{$character.screen-name}<instance>
    }

    method add-character(::?CLASS:D: MUGS::Character:D :$character!,
                         MUGS::Server::Session:D :$session!) {
        self.ensure-character-not-in-game($character);
        self.ensure-game-not-full;

        my $instance = self.wrap-character($character);
        %!participant{$character.screen-name} = hash(:$character, :$session, :$instance);

        my %data = new-count => %!participant.elems;
        self.add-event(CharacterJoined, :$character, :%data);

        self.start-game if self.ready-to-start-game;
    }

    method ready-to-start-game(::?CLASS:D: --> Bool:D) {
           $!gamestate == NotStarted
        && %.participant.elems >= %.config<start-players>
    }

    method start-game(::?CLASS:D:) {
        self.set-gamestate(InProgress);
    }

    method remove-character(::?CLASS:D: MUGS::Character:D $character) {
        self.ensure-character-in-game($character);
        %!participant{$character.screen-name}:delete;

        my %data = new-count => %!participant.elems;
        self.add-event(CharacterLeft, :$character, :%data);

        self.stop-game(Abandoned) if self.game-abandoned;
    }

    method game-abandoned(::?CLASS:D: --> Bool:D) {
           $!gamestate < Finished
        && %.participant.elems < %.config<min-players>
    }

    method stop-game(::?CLASS:D: GameState $new-state) {
        self.set-gamestate($new-state);
    }

    method participants(::?CLASS:D:) {
        %!participant.values
    }
}


#| A single session, as seen by the server
class MUGS::Server::Session {
    has                            $.id = NEXT-ID;
    has MUGS::Server:D             $.server     is required;
    has MUGS::Server::Connection:D $.connection is required;
    has MUGS::User                 $.user       is built(False);
    has Channel                    $.to-client  .= new;

    method start(::?CLASS:D:) {
        start react {
            whenever $!connection.from-client-supply -> $message {
                self.handle-client-message($message);
            }
            whenever $!to-client -> $message {
                $!connection.send-to-client($message);
            }
        }
    }

    method disconnect(::?CLASS:D:) {
        $!connection.disconnect;
        $!server.disconnect(self)
    }

    #| Log caught exceptions
    method log-exception(Exception:D :$exception!, MUGS::Message::Request:D :$request!) {
        return unless $*DEBUG || $exception !~~ X::MUGS;

        my $context = "in session $.id while processing request $request.id()"
                    ~ (" for user $.user.username()" if $.user);
        note "Caught exception $context: $exception.gist()";
    }

    #| Handle in-game requests from a particular character
    multi method handle-client-message(::?CLASS:D: MUGS::Message::Request::InGame:D $request) {
        # Convert exceptions to response errors
        CATCH {
            self.log-exception(:exception($_), :$request);

            when X::MUGS::Request { return self.error(RequestError, .message, $request.id) }
            when X::MUGS::Message { return self.error(RequestError, .message, $request.id) }
            default               { return self.error(ServerError,  .message, $request.id) }
        }

        # Authorization happens in the out-of-game multi, but certainly a user
        # must be logged in to do anything in-game.
        return self.auth-error($request.id) unless $.user;

        # Ensure this game exists, and enqueue the request for processing
        my $game-id = $request.game-id;
        my $game    = $!server.game-by-id($request.game-id);
        $game.enqueue-request(self, $request);
    }

    #| Handle out-of-game requests
    multi method handle-client-message(::?CLASS:D: MUGS::Message::Request:D $request) {
        # Convert exceptions to response errors
        CATCH {
            self.log-exception(:exception($_), :$request);

            when X::MUGS::Request { return self.error(RequestError, .message, $request.id) }
            when X::MUGS::Message { return self.error(RequestError, .message, $request.id) }
            default               { return self.error(ServerError,  .message, $request.id) }
        }

        # All authentication errors must return an identical error message to
        # avoid info leakage -- including trying to act without authenticating
        my &auth-error := { return self.auth-error($request.id) };
        auth-error unless $.user || $request.type eq 'authenticate'
                                 || $request.type eq 'create-account-owner';

        given $request.type {
            when 'authenticate' {
                # XXXX: Limited attempts; rate-limiting
                CATCH {
                    self.log-exception(:exception($_), :$request);

                    default { auth-error }
                }

                constant %schema
                    = method => Str, username => Str, password => Str but Optional;

                my $data = $request.validated-data(%schema);
                my ($username, $method) = $data< username method >;

                my $user;
                given $method {
                    # XXXX: Other, better authentication methods
                    when 'plaintext-password' {
                        my $password = $data<password> orelse auth-error;
                        $user = $!server.authenticate-user(:$username, :$password,
                                                           :session(self));
                    }
                    default { auth-error }
                }

                # Safety net for authenticators that don't just throw an
                # exception to the CATCH block above
                auth-error unless $user && $user ~~ MUGS::User;

                $.connection.debug-name = $username;
                $!user = $user;

                self.success({}, $request.id)
            }
            when 'create-account-owner' {
                # XXXX: Limited attempts; rate limiting
                CATCH {
                    self.log-exception(:exception($_), :$request);

                    default {
                        return self.error(RequestError, "Unable to create new user", $request.id);
                    }
                }

                constant %schema
                    = method => Str, username => Str, password => Str but Optional;

                my $data = $request.validated-data(%schema);
                my ($username, $method) = $data< username method >;

                my $user;
                given $method {
                    # XXXX: Other, better authentication methods
                    when 'plaintext-password' {
                        my $password = $data<password>
                            orelse return self.error(RequestError, "No password specified", $request.id);
                        $user = $!server.create-account-owner(:$username, :$password);
                    }
                    default {
                        return self.error(RequestError, "Unrecognized authentication method '$method'", $request.id);
                    }
                }

                return self.error(RequestError, "Cannot create user", $request.id)
                    unless $user && $user ~~ MUGS::User;

                $.connection.debug-name = $username;
                $!user = $user;

                self.success({}, $request.id)
            }
            when 'get-info-bundle' {
                # Space separated info-type identifiers for simplicity
                constant %schema = info-types => Str;
                my $info-types = $request.validated-data(%schema)<info-types>;
                my %info-types is Set = $info-types.words;
                my %info := $!server.get-info-bundle(:$!user, :%info-types);
                self.success(%info, $request.id);
            }
            when 'create-persona' {
                constant %schema = screen-name => Str;
                my $screen-name = $request.validated-data(%schema)<screen-name>;
                $!server.create-persona(:creator($!user), :$screen-name);
                self.success({}, $request.id);
            }
            when 'create-character' {
                constant %schema = screen-name => Str, persona-name => Str;
                my $data = $request.validated-data(%schema);
                my ($screen-name, $persona-name) = $data< screen-name persona-name >;
                $!server.create-character(:creator($!user), :$screen-name, :$persona-name);
                self.success({}, $request.id);
            }
            when 'new-game' {
                constant %schema = game-type => Str, config => Map;
                my $data = $request.validated-data(%schema);
                my ($game-type, $config) = $data< game-type config >;
                my $game-id = $!server.new-game(:creator($!user), :$game-type, :$config);
                self.success({ :$game-id }, $request.id)
            }
            when 'join-game' {
                constant %schema = game-type => Str, game-id => GameID,
                                   character-name => Str;
                my $data = $request.validated-data(%schema);
                my ($game-type, $game-id, $character-name)
                    = $data< game-type game-id character-name >;

                # XXXX: Permissions to use character and to join game?
                $!server.ensure-game-has-type($game-id, $game-type);
                my $game      = $!server.game-by-id($game-id);
                my $character = $!server.character-by-name($character-name);
                $game.add-character(:$character, :session(self));
                my $initial-state = $game.initial-state(:$character);

                self.success({ :$initial-state }, $request.id)
            }
            default {
                self.error(RequestError, "Unknown out-of-game request type '$_'", $request.id)
            }
        }
    }

    #| Handle unparseable requests
    multi method handle-client-message(::?CLASS:D: $bad-request) {
        self.error(RequestError, 'Unparseable request', 0);
    }

    method auth-error($request-id) {
        self.error(RequestError, 'Authentication failed', $request-id)
    }

    method error(Status $status, Str $error, $request-id) {
        $!to-client.send:
            MUGS::Message::Response.new(:$status, :data(hash(:$error)), :$request-id);
    }

    method success(%data, $request-id) {
        $!to-client.send:
            MUGS::Message::Response.new(:status(Success), :%data, :$request-id);
    }


    # XXXX: Ruminations on push-message and friends:
    # * Targets:
    #   * Network/namespace, server, game, session
    #   * Account, user, persona, character
    #   * Game is optional context for character and maybe persona
    #   * Should target-type be an enum?
    # * Message to session should be outside of any "real" game
    #   * Should there be an always-present implied game?
    #   * Should that be the lobby?
    #     * Is the lobby special in allowing multi-session-join?
    #       * No, every session's lobby is unique, and only allows single player
    #     * What about account or system admin UIs?  Are these "games" too?
    #   * What about urgent operational messages, like system alerts?
    # * Message to account, user, persona, or character *not* in a game should
    #   be queued for delivery when that target is again available
    #   * Change in queued message status should be indicated to player in a
    #     non-distracting way
    #   * Persona and character queued messages should be indicated even if the
    #     player is not using them during the current session, so they can look
    #     at the messages if desired (possibly requiring temporary switch to
    #     the other identity)
    # * Message to character in game should be delivered immediately in that
    #   game context.

    # NOTE: $game-id is optional for push-message variants; if missing, the
    #       message is outside any game

    multi method push-message(MUGS::Character:D :$character!,
                              MUGS::Character:D :$sender!, :$message!,
                              Str:D :$message-type!, GameID :$game-id) {
        self.push-message(:$message, :$message-type, :$game-id,
                          :sender($sender.screen-name),
                          :target($character.screen-name),
                          :target-type<character>);
    }

    multi method push-message(Str:D :$message!, Str:D :$message-type!,
                              Str:D :$target!, Str:D :$target-type!,
                              Str:D :$sender!, GameID :$game-id) {
        my %data := hash(:$message-type, :$target-type, :$target, :$message, :$sender);
        %data<game-id> = $_ with $game-id;
        self.push(:type<message>, :%data);
    }

    method push-game-update(GameID:D :$game-id!, MUGS::Character:D :$character!,
                            :%update!) {
        my %data := hash(|%update, :$game-id, :character-name($character.screen-name));
        self.push(:type<game-update>, :%data);
    }

    method push-pack(Str:D :$type!, :$pack!) {
        $!to-client.send: MUGS::Message::PushPack.new(:$type, :$pack);
    }

    method push(Str:D :$type!, :%data!) {
        $!to-client.send: MUGS::Message::Push.new(:$type, :%data);
    }
}


#| A simple game server
class MUGS::Server
 does Pluggable
 does MUGS::Util::ImplementationRegistry[MUGS::Server::Game] {
    has MUGS::Server::Session:D              %!session;
    has MUGS::Server::Game:D                 %!game;
    has MUGS::Server::Storage::Identities:D  $.identity-store   is required;
    has MUGS::Server::Storage::Credentials:D $.credential-store is required;


    method load-game-plugins() {
        my regex top-level-game { ^ 'MUGS::Server::Game::' \w+ $ }
        my @plugins = self.plugins(:plugins-namespace('Game'),
                                   :name-matcher(&top-level-game));
    }

    method !ensure-game-type-exists($game-type) {
        X::MUGS::Message::InvalidEntity.new(:type('game type'), :id($game-type)).throw
            unless self.implementation-exists($game-type);
    }

    method !ensure-game-exists($game-id) {
        X::MUGS::Message::InvalidEntity.new(:type<game>, :id($game-id)).throw
            unless %!game{$game-id}:exists;
    }

    method ensure-game-has-type($game-id, $game-type) {
        self!ensure-game-exists($game-id);
        self!ensure-game-type-exists($game-type);

        X::MUGS::Server::GameTypeMismatch.new(:$game-id, :$game-type).throw
            unless %!game{$game-id}.game-type eq $game-type;
    }

    method game-by-id(::?CLASS:D: GameID:D $game-id) {
        %!game{$game-id}
            or X::MUGS::Message::InvalidEntity.new(:type<game>, :id($game-id)).throw;
    }

    method character-by-name(::?CLASS:D: Str:D $character-name) {
        $!identity-store.character-by-name($character-name)
    }

    method accept-connection(::?CLASS:D: :$connection!) {
        my $session = MUGS::Server::Session.new(:server(self), :$connection);
        $session.start;
        %!session{$session.id} = $session;
        MUGS::Server::LogTimelineSchema::ConnectionAccepted.log(:session-id($session.id));
        $connection
    }

    method disconnect(::?CLASS:D: MUGS::Server::Session:D $session) {
        MUGS::Server::LogTimelineSchema::ConnectionDropped.log(:session-id($session.id));
        %!session{$session.id}:delete;
    }

    multi method create-account-owner(::?CLASS:D: Str:D :$username!,
                                      MUGS::Authentication::Credential:D :$credential!) {
        # XXXX: Detect failure to create account or user
        my $account = $!identity-store.new-account;
        my $user    = $!identity-store.new-user(:$username, :$account);
        # XXXX: Mark user as account owner
        $!credential-store.add-credential(:$username, :$credential);
        $user
    }

    multi method create-account-owner(::?CLASS:D: Str:D :$username!, Str:D :$password!) {
        my $credential = MUGS::Authentication::Password.new(:$password);
        self.create-account-owner(:$username, :$credential);
    }

    method authenticate-user(::?CLASS:D: :$username!, :$session!, :$password!) {
        my $credentials = $!credential-store.credentials-for-username($username, :auth-type<password>);

        if $credentials.first(*.verify($password)) {
            MUGS::Server::LogTimelineSchema::UserAuthSuccess.log(:$username, :session-id($session.id));
            $!identity-store.user-by-name($username);
        }
        else {
            MUGS::Server::LogTimelineSchema::UserAuthFailure.log(:$username, :session-id($session.id));
            X::MUGS::Server::InvalidCredentials.new(:$username).throw;
        }
    }

    method get-info-bundle(::?CLASS:D: MUGS::User:D :$user!, :%info-types!) {
        my %info;

        for < available-identities available-game-types active-games > {
            %info{$_} := self."get-info-$_"($user) if %info-types{$_};
        }

        %info
    }

    method get-info-available-identities(::?CLASS:D: MUGS::User:D $user) {
        my @personas = $user.available-personas.map: {
            my @characters = .characters.map(*.screen-name);
            hash(persona => .screen-name, :@characters)
        }
    }

    method get-info-available-game-types(::?CLASS:D: MUGS::User:D $user) {
        # XXXX: Permissions to see game types?
        my @game-types = self.known-implementations.map: {
            my $impl         = self.implementation-class($_);
            my $game-desc    = $impl.game-desc;
            my @genre-tags   = $impl.genre-tags;
            my @content-tags = $impl.content-tags;
            my @config-form  = $impl.config-form.map: {
                my %field    = .< field section desc default visible-locally >:kv;
                %field<type> = .<type>.^name;
                %field
            };

            hash(game-type => $_, :$game-desc, :@genre-tags, :@content-tags, :@config-form)
        }
    }

    method get-info-active-games(::?CLASS:D: MUGS::User:D $user) {
        my @characters is Set = $user.available-personas.map(*.characters).flat.map(*.screen-name);
        my @active-games = %!game.kv.map: -> GameID() $game-id, $game {
            my $game-type           = $game.game-type;
            my $gamestate           = $game.gamestate;
            my $config              = $game.config;
            my $created-by-me       = $game.creator === $user
                                   || $game.creator.username eq $user.username;
            my $num-participants    = $game.participants.elems;
            my @participants is Set = $game.participants.map(*<character>.screen-name);
            my @my-characters       = (@characters ∩ @participants).keys;

            # Don't include private or finished games that user is not already
            # associated with (the creator or controlling a joined character)
            next unless $created-by-me || @my-characters
                     || !$config<invites-only> && $game.gamestate < Finished;

            # XXXX: Permissions to view games/configs/details?

            hash(:$game-id, :$game-type, :$gamestate, :$config,
                 :$created-by-me, :$num-participants, :@my-characters)
        }
    }

    method create-persona(::?CLASS:D: MUGS::User:D :$creator!, Str:D :$screen-name!) {
        # XXXX: Permission to create a persona
        # XXXX: Detect failure to create persona
        my $account = $creator.account;
        my $persona = $!identity-store.new-persona(:$screen-name, :$account);
        $persona.add-authorized-users($creator);
        # XXXX: Mark user as persona creator
        $persona
    }

    multi method create-character(::?CLASS:D: MUGS::User:D :$creator!,
                                  MUGS::Persona:D :$persona!,
                                  Str:D :$screen-name!) {
        # XXXX: Permission to use persona and create a character
        # XXXX: Detect failure to create character
        my $character = $!identity-store.new-character(:$screen-name, :$persona);
        # XXXX: Mark user as character creator
        $character
    }

    multi method create-character(::?CLASS:D: MUGS::User:D :$creator!,
                                  Str:D :$persona-name!,
                                  Str:D :$screen-name!) {
        # XXXX: Detect failure to load persona
        my $persona = $!identity-store.persona-by-name($persona-name);
        self.create-character(:$creator, :$persona, :$screen-name);
    }

    method new-game(::?CLASS:D: MUGS::User:D :$creator!, Str:D :$game-type!, :%config!) {
        self!ensure-game-type-exists($game-type);
        my $game = self.implementation-class($game-type).new(:$creator, :%config, :server(self));
        $game.start-dispatcher;
        %!game{$game.id} = $game;
        MUGS::Server::LogTimelineSchema::GameCreated.log(:$game-type, :game-id($game.id), :creator($creator.username));
        $game.id;
    }

    method broadcast-to-sessions(::?CLASS:D: :$message!) {
        for %!session.values -> $session {
            $session.push-message(:$message, :message-type<broadcast>,
                                  :target<active-session>, :target-type<session>);
        }
    }
}
