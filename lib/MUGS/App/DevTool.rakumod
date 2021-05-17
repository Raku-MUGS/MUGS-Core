# ABSTRACT: Tools for simplifying common MUGS developer actions


use MUGS::App::LocalTool;


class MUGS::App::DevTool is MUGS::App::LocalTool {
    has %.known;

    #| Make a type of thing known, based on finding a module implementing it
    method make-known($type, $path) {
        my $thing = $path.basename.subst(/'.' .*/, '');
        %!known{$type}{$thing} = True;
    }

    #| Determine all known UIs, games, and genres
    method find-known() {
        self.make-known('ui',    $_) for dir 'lib/MUGS/UI';
        self.make-known('game',  $_) for dir 'lib/MUGS/Client/Game';
        self.make-known('game',  $_) for dir 'lib/MUGS/Server/Game';
        self.make-known('genre', $_) for dir 'lib/MUGS/Client/Genre';
        self.make-known('genre', $_) for dir 'lib/MUGS/Server/Genre';

        for %!known<ui>.keys -> $ui {
            if "lib/MUGS/UI/$ui/Game".IO.d {
                self.make-known('game', $_)  for dir "lib/MUGS/UI/$ui/Game";
            }
            if "lib/MUGS/UI/$ui/Genre".IO.d {
                self.make-known('genre', $_) for dir "lib/MUGS/UI/$ui/Genre";
            }
        }
    }

    #| Exit with an error if a genre already exists
    method ensure-new-genre(Str:D $genre) {
        self.ensure: { not %!known<genre>{$genre} }, "Genre '$genre' already exists.";
    }

    #| Exit with an error unless a genre already exists
    method ensure-genre-exists(Str:D $genre) {
        self.ensure: { %!known<genre>{$genre} }, "Genre '$genre' does not exist.";
    }

    #| Exit with an error if a game already exists
    method ensure-new-game(Str:D $game) {
        self.ensure: { not %!known<game>{$game} }, "Game '$game' already exists.";
    }

    #| Exit with an error unless all requested UIs exist
    method ensure-uis-exist(@UIs) {
        for @UIs -> $ui {
            self.ensure: { %!known<ui>{$ui} }, "UI '$ui' does not exist.";
        }
    }


    #| Do basic startup prep
    method prep() {
        self.ensure-at-repo-root;
        self.find-known;
    }
}


#| Create a new UI type
multi MAIN('new-ui-type', Str:D $ui-type) is export {
    my $tool = MUGS::App::DevTool.new;
    $tool.ensure-at-repo-parent;

    my $app   = 'MUGS::App::' ~ $ui-type;
    my $class = 'MUGS::UI::' ~ $ui-type;
    my $repo  = $class.subst('::', '-', :g);
    $tool.ensure: { !$repo.IO.e }, "Directory '$repo' already exists.";

    $tool.run-or-exit(« mi6 new $class », :force);
    chdir $repo;
    $tool.run-or-exit($_, :force) for
        « git commit -m "Initial mi6 template" »,
        « git branch -M main »,
    ;

    $tool.additional-step('Creating directories');
    my $lib-dir = "lib/MUGS/UI/$ui-type";
    .put, .IO.mkdir for « docs lib/MUGS/App $lib-dir
                          "$lib-dir/Game" "$lib-dir/Genre" »;

    $tool.additional-step('Adding MUGS-specific files');

    my $MUGS-version = $?DISTRIBUTION.meta<version>;
    my $bin-file     = 'bin/mugs-' ~ $ui-type.lc.subst(/^ 'web' /, 'web-');
    my $app-file     = "lib/MUGS/App/{$ui-type}.rakumod";
    my $test-file    = "t/00-use.rakutest";

    put $bin-file;
    spurt($bin-file, q:to/BIN_FILE/);
        #!/usr/bin/env raku
        use v6.d;
        BEGIN put 'Loading MUGS.' if $*OUT.t;
        use \qq[$app];
        BIN_FILE

    put $app-file;
    spurt($app-file, q:to/APP_MODULE/);
        # ABSTRACT: Core logic to set up and run a \qq[$ui-type] game

        # XXXX: use \qq[$ui-type] app module here

        use MUGS::Core;
        use MUGS::App::LocalUI;
        use \qq[$class];


        # Use subcommand MAIN args
        %PROCESS::SUB-MAIN-OPTS = :named-anywhere;


        #| \qq[$ui-type] App
        class \qq[$app] is MUGS::App::LocalUI {

            method ui-type() { '\qq[$ui-type]' }

            #| Connect to server and authenticate as a valid user
            method ensure-authenticated-session(Str $server, Str $universe) {
                my $decoded = self.decode-and-connect($server, $universe);
                my ($username, $password) = self.initial-userpass($decoded);

                # XXXX: Should allow player to correct errors and retry or exit
                await $.session.authenticate(:$username, :$password);
            }

            #| Start actively playing current game UI
            method play-current-game() {
                # XXXX: Enter \qq[$ui-type] main loop here
            }
        }


        #| Common options that work for all subcommands
        my $common-args = :(Str :$server, Str :$universe, Bool :$debug);

        #| Add description of common arguments/options to standard USAGE
        sub GENERATE-USAGE(&main, |capture) is export {
            &*GENERATE-USAGE(&main, |capture).subst(' <options>', '', :g)
            ~ q:to/OPTIONS/.trim-trailing;


                Common options for all commands:
                  --server=<Str>    Specify an external server (defaults to internal)
                  --universe=<Str>  Specify a local universe (internal server only)
                  --debug           Enable debug output
                OPTIONS
        }


        #| Play a requested \qq[$ui-type] game
        multi MAIN($game-type, |options where $common-args) is export {
            play-via-local-ui(\qq[$app], :$game-type, |options)
        }
        APP_MODULE

    put $test-file;
    spurt($test-file, q:to/USE_TEST/);
        use v6.d;
        use Test;

        # Will need at least these Core and Games versions to use these UI modules
        use MUGS::Core:ver<\qq[$MUGS-version]>;
        use MUGS::Games:ver<\qq[$MUGS-version]>;


        ### TUI INTERFACE

        use \qq[$class];
        use MUGS::App::\qq[$ui-type] Empty;


        pass "all modules loaded successfully";


        done-testing;
        USE_TEST

    $tool.run-or-exit($_, :force) for
        « chmod +x $bin-file »,
        « git add $bin-file $app-file $test-file »,
        « git rm t/01-basic.rakutest »,  # Redundant with 00-use
        « git commit -m "Add MUGS-specific files" »,
        « git status »,
    ;

    $tool.all-success;
}


#| Create a new game genre for one or more UIs
multi MAIN('new-genre', Str:D $genre, *@UIs where +*, Str:D :$desc!) is export {
    my $tool = MUGS::App::DevTool.new;
    $tool.prep;
    $tool.ensure-new-genre($genre);
    $tool.ensure-uis-exist(@UIs);

    mkdir "lib/MUGS/Server/Genre";
    spurt("lib/MUGS/Server/Genre/$genre.rakumod", q:to/SERVER/);
        # ABSTRACT: General server for \qq[$desc] games

        use MUGS::Core;
        use MUGS::Server;


        #| Server side of \qq[$desc] games
        class MUGS::Server::Genre::\qq[$genre] is MUGS::Server::Game {
            method valid-action-types() { < nop foo > }

            method ensure-action-valid($action) {
                callsame;

                if $action<type> eq 'foo' {
                }
            }

            method process-action-foo(::?CLASS:D: MUGS::Character:D :$character!, :$action!) {
            }

            method game-status(::?CLASS:D: $action-result) {
                hash(|callsame)
            }
        }
        SERVER

    mkdir "lib/MUGS/Client/Genre";
    spurt("lib/MUGS/Client/Genre/$genre.rakumod", q:to/CLIENT/);
        # ABSTRACT: General client for \qq[$desc] games

        use MUGS::Core;
        use MUGS::Client;


        #| Client side of \qq[$desc] games
        class MUGS::Client::Genre::\qq[$genre] is MUGS::Client::Game {
            # method send-unparsed-input($input, &on-success?) {
            #     self.action-promise: hash(:type<unparsed-input>, :$input), &on-success;
            # }
        }
        CLIENT

    for @UIs -> $ui {
        my $ui-desc = $ui.ends-with('I') ?? $ui !! $ui ~ ' interface';
        mkdir "lib/MUGS/UI/$ui/Genre";
        spurt("lib/MUGS/UI/$ui/Genre/$genre.rakumod", q:to/UI/);
            # ABSTRACT: General \qq[$ui-desc] for \qq[$desc] games

            use MUGS::Core;
            use MUGS::Client::Genre::\qq[$genre];
            use MUGS::UI::\qq[$ui];


            #| \qq[$ui-desc] for \qq[$desc] games
            class MUGS::UI::\qq[$ui]::Genre::\qq[$genre] is MUGS::UI::\qq[$ui]::Game {
            }
            UI
    }
}


#| Create a new game for one or more UIs, optionally based on a known genre
multi MAIN('new-game', Str:D $game-class, *@UIs where +*, :$genre!, Str:D :$desc!) is export {
    my $tool = MUGS::App::DevTool.new;
    $tool.prep;
    $tool.ensure-new-game($game-class);
    $tool.ensure-uis-exist(@UIs);

    $tool.ensure: { $genre ~~ Str || $genre === False },
                  'Must specify --genre=GenreName or --/genre';
    $tool.ensure-genre-exists($genre) if $genre;

    my $game-type     = $game-class.subst(/(<:lower>)(<:upper>)/, { "$0-$1" }, :g).lc;
    my $server-base   = $genre ?? "MUGS::Server::Genre::$genre" !! "MUGS::Server::Game";
    my $server-module = $genre ?? "MUGS::Server::Genre::$genre" !! "MUGS::Server";
    my $client-base   = $genre ?? "MUGS::Client::Genre::$genre" !! "MUGS::Client::Game";
    my $client-module = $genre ?? "MUGS::Client::Genre::$genre" !! "MUGS::Client";

    my $server-extra-methods = '';
    unless $genre {
        $server-extra-methods = q:to/METHODS/;

            method valid-action-types() { < nop foo > }

            method ensure-action-valid($action) {
                callsame;

                if $action<type> eq 'foo' {
                }
            }

            method process-action-foo(::?CLASS:D: MUGS::Character:D :$character!, :$action!) {
            }

            method game-status(::?CLASS:D: $action-result) {
                hash(|callsame)
            }
        METHODS
    }

    mkdir "lib/MUGS/Server/Game";
    spurt("lib/MUGS/Server/Game/$game-class.rakumod", q:to/SERVER/);
        # ABSTRACT: Server for \qq[$desc] games

        use MUGS::Core;
        use \qq[$server-module];


        #| Server side of \qq[$desc] game
        class MUGS::Server::Game::\qq[$game-class] is \qq[$server-base] {
            method game-type() { '\qq[$game-type]' }
        \qq[$server-extra-methods]}


        # Register this class as a valid server class
        MUGS::Server::Game::\qq[$game-class].register;
        SERVER

    mkdir "lib/MUGS/Client/Game";
    spurt("lib/MUGS/Client/Game/$game-class.rakumod", q:to/CLIENT/);
        # ABSTRACT: Client for \qq[$desc] games

        use MUGS::Core;
        use \qq[$client-module];


        #| Client side of \qq[$desc] game
        class MUGS::Client::Game::\qq[$game-class] is \qq[$client-base] {
            method game-type() { '\qq[$game-type]' }
        }


        # Register this class as a valid client
        MUGS::Client::Game::\qq[$game-class].register;
        CLIENT

    for @UIs -> $ui {
        my $ui-desc   = $ui.ends-with('I') ?? $ui !! $ui ~ ' interface';
        my $ui-base   = $genre ?? "MUGS::UI::{$ui}::Genre::$genre" !! "MUGS::UI::{$ui}::Game";
        my $ui-module = $genre ?? "MUGS::UI::{$ui}::Genre::$genre" !! "MUGS::UI::{$ui}";

        mkdir "lib/MUGS/UI/$ui/Game";
        spurt("lib/MUGS/UI/$ui/Game/$game-class.rakumod", q:to/UI/);
            # ABSTRACT: \qq[$ui-desc] for \qq[$desc] games

            use MUGS::Core;
            use MUGS::Client::Game::\qq[$game-class];
            use \qq[$ui-module];


            #| \qq[$ui-desc] for a \qq[$desc] game
            class MUGS::UI::\qq[$ui]::Game::\qq[$game-class] is \qq[$ui-base] {
                method game-type() { '\qq[$game-type]' }
            }


            # Register this class as a valid game UI
            MUGS::UI::\qq[$ui]::Game::\qq[$game-class].register;
            UI
    }
}
