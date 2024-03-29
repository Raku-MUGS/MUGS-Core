# ABSTRACT: Common logic used by local UIs (as opposed to e.g. web gateways)

use MUGS::Core;
use MUGS::Util::Config;

use MUGS::Client;
use MUGS::Client::Connection::Supplier;

# Most of the precompile and load time is in the next two `use` lines.
# I have no idea yet why they are _particularly_ worse than the others.
use MUGS::Client::Connection::WebSocket;
use MUGS::Client::Game::Lobby;

use MUGS::Server::Universe;
use MUGS::Server::Stub;
use MUGS::UI;

use Cro::Uri;


#| Base class for local UIs
# XXXX: Needs better error handling throughout
class MUGS::App::LocalUI {
    # XXXX: Currently only able to connect to one server at a time
    has MUGS::Client::Session     $.session;
    has MUGS::Util::Config        $.config;
    has MUGS::Client::Game::Lobby $.lobby-client;

    has Str  $.osname;
    has Bool $.is-win;
    has @.user-languages;

    # MUST override in UI-specific subclasses
    method ui-type()           { ... }
    method play-current-game() { ... }
    method ensure-authenticated-session(Str $server, Str $universe) { ... }

    # MAY override in UI-specific subclasses
    method game-ui-opts() { hash() }

    #| Initialize the overall MUGS client app
    #  Should exit with an appropriate message if any required initialization
    #  fails, and be as fast as possible -- before this completes, nothing
    #  appears to be happening.
    method initialize() {
        self.gather-os-info;
        self.load-configs-or-exit;
    }

    #| Gather OS-specific information, such as locale preferences
    method gather-os-info() {
        # The next two lines are basically a portable version of
        # Rakudo::Internals.IS-WIN, using the Raku standard APIs
        $!osname = VM.osname.lc.trans(' ' => '');
        $!is-win = $!osname ∈ < mswin32 mingw msys cygwin >;

        # Detect language preferences: Linux and Un*x variants
        if (%*ENV<LANGUAGE> // %*ENV<LANG>) || 'en_US' -> $languages {
            @!user-languages = $languages.split(':').map:
                                   { .subst(/'.' .*/, '').trans('_' => '-') };
        }
        # XXXX: Need to add darwin and is-win variants; for ideas see:
        # https://github.com/alabamenhu/UserLanguage/blob/master/lib/Intl/UserLanguage.pm6
    }

    #| Load user configs or exit with errors
    method load-configs-or-exit() {
        $!config = MUGS::Util::Config.new(:type<user>);

        if $!config.load-defaults -> @errors {
            self.exit-with-errors('Could not load user defaults:', @errors);
        }
        elsif $!config.load-config-file -> @errors {
            # Don't complain if the user has no config file yet
            if @errors > 1 || @errors[0] !~~ X::MUGS::File::Missing {
                self.exit-with-errors('Could not load user config:', @errors);
            }
        }
    }

    #| Load ui-type-specific config key (or its default, if not set),
    #| falling back to Common defaults if no ui-type-specific default either
    method ui-config(Str:D $key) {
           $.config.value('UI', $.ui-type, $key)
        // $.config.value('UI', 'Common',  $key)
    }

    #| Load ui-type-specific config default, ignoring user's config settings,
    #| falling back to Common defaults if no ui-type-specific default exists
    method ui-default(Str:D $key) {
           $.config.default('UI', $.ui-type, $key)
        // $.config.default('UI', 'Common',  $key)
    }

    #| Disconnect if needed, then exit with error messages for the player
    method exit-with-errors(Str:D $intro, @errors) {
        self.shutdown;

        note $intro;
        .message.indent(4).note for @errors;

        exit 1;
    }

    #| Load all relevant plugins
    method load-plugins() {
        self.load-client-plugins;
        self.load-ui-plugins;
    }

    #| Load Client plugins
    method load-client-plugins() {
        MUGS::Client.load-game-plugins;
    }

    #| Load UI plugins for this UI type
    method load-ui-plugins() {
        MUGS::UI.load-game-plugins(self.ui-type);
    }

    #| Shut down the overall MUGS client app (as cleanly as possible)
    method shutdown() {
        self.disconnect;
    }

    #| Determine if session is internal-only (and thus need not authenticate)
    method session-is-internal(MUGS::Client::Session $session = $!session) {
        $session && $session.connection ~~ MUGS::Client::Connection::Supplier
                 && $session.server     ~~ MUGS::Server
    }

    #| Decode user's server request and connect to it or error out
    method decode-and-connect(Str $server, Str $universe) {
        my $decoded = self.decode-server($server);

        # Try to connect, bailing out if unable to do so
        unless my $session = TRY({ self.connect($decoded<url> // $decoded<server>, $universe) }) {
            self.exit-with-errors("Unable to connect to MUGS server '$decoded<server>':", [$!]);
        }

        $decoded
    }

    #| Decode a user's specified server to determine its URL, username, and password
    method decode-server(Str $server) {
        my $srv = $server || $.config.value('Servers', 'DEFAULT') || 'internal';
        my ($url, $user, $pass);

        if $.config.value('Servers', $srv) {
            $url  = $.config.value('Servers', $srv, 'url');
            $user = $.config.value('Servers', $srv, 'user');
            $pass = $.config.value('Servers', $srv, 'pass');
        }
        elsif Cro::Uri.parse($srv) -> $parsed {
            $user = $parsed.userinfo;
            $url  = $srv;
        }
        elsif Cro::Uri::GenericParser.parse($srv, :rule<authority>,
                                            :actions(Cro::Uri::GenericActions)) -> $parsed {
            $user = $parsed.ast<userinfo>;
            $url  = 'wss://' ~ $parsed.ast<host>
                  ~ (":$_" with $parsed.ast<port>)
                  ~ '/mugs-ws';
        }

        { :server($srv), :$url, :username($user), :password($pass) }
    }

    #| Connect to server (creating a local server if necessary)
    method connect(Str $server, Str $universe?) {
        self.disconnect;
        $!session = $server ?? self.connect-to-websocket-server($server)
                            !! self.connect-to-local-server($universe);
    }

    #| Create and connect to a local-in-memory server with stub identities
    method connect-to-local-server(Str $universe?) {
        # Create local server, using either an existing universe or an in-memory stub
        my $server = $universe ?? create-universe-mugs-server($universe)
                               !! create-stub-mugs-server(:include-default-user);

        # Load game plugins into new server
        $server.load-game-plugins;

        # Connect a client session to the local server
        my $connector = MUGS::Client::Connection::Supplier;
        MUGS::Client::Session.connect(:$connector, :$server)
    }


    #| Connect to an existing WebSocket server
    method connect-to-websocket-server($server) {
        my $ca-file = %*ENV<MUGS_WEBSOCKET_TLS_CA> ||
                      %?RESOURCES<fake-tls/ca-crt.pem> ||
                       'resources/fake-tls/ca-crt.pem';
        my %ca = :$ca-file;

        my $connector = MUGS::Client::Connection::WebSocket;
        MUGS::Client::Session.connect(:$connector, :$server, :%ca)
    }

    #| Disconnect from server
    method disconnect() {
        $!session.disconnect if $!session;
        $!session = Nil;
        $!lobby-client = Nil;
    }

    #| Determine an initial username and password, given decoded server info
    method initial-userpass(%decoded) {
        my $username  = %decoded<username>
                     || $.config.value('Servers', %decoded<server>, 'user');
        my $password  = $.config.value('Servers', %decoded<server>, 'pass') // '';

        ($username, $password)
    }

    #| Choose identities (persona and character) to use when creating or joining games
    method choose-identities() {
        my $data = await $.session.get-info-bundle([< available-identities >]);
        with $data<available-identities> {
            if .elems {
                $.session.default-persona   = .[0]<persona>;
                $.session.default-character = .[0]<characters>[0] // '';
            }
        }
    }

    #| Create a new (singleton) lobby client
    method start-lobby-client() {
        $!lobby-client = self.new-game-client(game-type => 'lobby');
    }

    #| Create (if needed) and then join a game of the requested game-type
    method new-game-client(Str:D :$game-type, GameID :$game-id is copy, :%config) {
        # XXXX: What if the player provides *both* a $game-id and a %config?
        # XXXX: Turn this into a promise chain
        # XXXX: What if the server can't create the game, or the character can't join?
        $game-id   ||= await $!session.new-game(:$game-type, :%config);
        my $client   = await $!session.join-game(:$game-type, :$game-id);
    }

    #| Create and initialize a new game UI for a given game type and client
    method launch-game-ui(Str:D :$game-type, MUGS::Client::Game:D :$client) {
        my $game-ui-class = MUGS::UI.ui-class($.ui-type, $game-type);
        my $game-ui       = $game-ui-class.new(:$client, :app-ui(self),
                                               |self.game-ui-opts);

        $game-ui.initialize;
        $game-ui
    }
}


#| Play the chosen game using either a WebSocket server or a local in-memory server
sub play-via-local-ui(MUGS::App::LocalUI:U $app-ui-class,
                      Str:D :$game-type, GameID :$game-id, :%config,
                      Str :$server, Str :$universe, UInt :$debug,
                      *%ui-options) is export {
    # Set up local app UI; should exit with message on error
    my $*DEBUG = $debug // +(%*ENV<MUGS_DEBUG> // 0);
    my $app-ui = $app-ui-class.new(|%ui-options);
    $app-ui.initialize;

    # INVARIANTS REQUIRED AT THIS POINT:
    #   * UI is (minimally) initialized
    #   * Logging and debug facilities are available
    #   * User config (and config defaults) loaded successfully
    #   * User's locale has been activated

    # Load plugins and confirm that needed plugins exist for requested game-type
    $app-ui.load-plugins;

    $app-ui.exit-with-errors("Cannot launch '$game-type'; missing client plugin.", [])
        unless MUGS::Client.implementation-exists($game-type);

    $app-ui.exit-with-errors("Cannot launch '$game-type'; missing UI plugin.", [])
        unless MUGS::UI.ui-exists($app-ui.ui-type, $game-type);

    # INVARIANTS REQUIRED AT THIS POINT:
    #   * All plugins required for requested game are loaded

    # Connect to server and authenticate as a valid user;
    # should allow player to correct errors and retry or exit
    $app-ui.ensure-authenticated-session($server, $universe);

    # INVARIANTS REQUIRED AT THIS POINT:
    #   * Server session has connected
    #   * Session has been authenticated with a valid user
    #   * Session has been recently confirmed still active

    # Choose identities to use when creating and joining games
    $app-ui.choose-identities;

    # Set up a lobby client
    $app-ui.start-lobby-client;

    # Create (if needed) and then join a game of the requested game-type
    my $client = $game-type eq 'lobby'
                 ?? $app-ui.lobby-client
                 !! $app-ui.new-game-client(:$game-type, :$game-id, :%config);

    # Create and initialize the game UI
    $app-ui.launch-game-ui(:$game-type, :$client);

    # Play games until all done
    $app-ui.play-current-game;

    # Clean up
    $app-ui.shutdown;
}


#| Allow certain exceptions/backtraces when DEBUG is true, otherwise defang
sub TRY(&code) is export { $*DEBUG ?? code() !! try code() }
