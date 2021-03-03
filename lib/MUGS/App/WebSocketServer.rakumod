# ABSTRACT: Core logic to set up and run a WebSocket MUGS server

use Cro::HTTP::Log::File;
use Cro::HTTP::Server;

use MUGS::Server::Universe;
use MUGS::Server::Stub;

use MUGS::App::WebSocketServer::Routes;


# Use subcommand MAIN args
%PROCESS::SUB-MAIN-OPTS = :named-anywhere;


#| Create a Cro::HTTP::Server able to speak the WebSocket protocol
sub create-websocket-server(:$application!, Str:D :$host!, UInt:D :$port!,
                            Bool:D :$secure!, :$private-key-file!, :$certificate-file!) {
    my Cro::Service $http = Cro::HTTP::Server.new(
        http => <1.1>, :$host, :$port, :$application,
        |(tls => %( :$private-key-file, :$certificate-file ) if $secure),
        after => [
            Cro::HTTP::Log::File.new(logs => $*OUT, errors => $*ERR)
        ]
    );
}


#| Launch a WebSocket MUGS server listening on host:port
sub MAIN( Str:D :$universe = %*ENV<MUGS_WEBSOCKET_UNIVERSE> || 'default',
          Str:D :$host = %*ENV<MUGS_WEBSOCKET_HOST> || 'localhost',
         UInt:D :$port = %*ENV<MUGS_WEBSOCKET_PORT> || 10_000,
         :$private-key-file = %*ENV<MUGS_WEBSOCKET_TLS_KEY> ||
                              %?RESOURCES<fake-tls/server-key.pem> ||
                               'resources/fake-tls/server-key.pem',
         :$certificate-file = %*ENV<MUGS_WEBSOCKET_TLS_CERT> ||
                              %?RESOURCES<fake-tls/server-crt.pem> ||
                               'resources/fake-tls/server-crt.pem',
         Bool:D :$secure = True, Bool:D :$debug = True) is export {

    $PROCESS::DEBUG = $debug;
    put "Using {$universe ?? "universe '$universe'" !! 'internal stub universe'}.";
    my $mugs-server = $universe ?? create-universe-mugs-server($universe)
                                !! create-stub-mugs-server;

    put 'Loading games.';
    $mugs-server.load-game-plugins;
    my @loaded = $mugs-server.known-implementations.sort;
    put "Loaded: @loaded[]";

    put 'Starting WebSocket server.';
    my $application = routes(:$mugs-server);
    my $ws-server   = create-websocket-server(:$application, :$host, :$port,
                                              :$secure, :$private-key-file,
                                              :$certificate-file);

    $ws-server.start;
    my $root = $application.handlers[0].implementation.signature.params[0].constraint_list[0];
    my $url  = "ws{'s' if $secure}://$host:$port/$root";
    put "Listening at $url";
    react {
        whenever signal(SIGINT) {
            put 'Shutting down.';
            $ws-server.stop;
            done;
        }
    }
}
