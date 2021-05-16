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
