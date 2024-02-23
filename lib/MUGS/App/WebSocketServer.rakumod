# ABSTRACT: Core logic to set up and run a WebSocket MUGS server

use MUGS::App::CroServer;
use MUGS::App::WebSocketServer::Routes;
use MUGS::Server::Universe;
use MUGS::Server::Stub;


# Use subcommand MAIN args
PROCESS::<%SUB-MAIN-OPTS> := :named-anywhere;


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
         Bool:D :$secure = True, UInt :$debug) is export {

    $PROCESS::DEBUG = $debug // +(%*ENV<MUGS_DEBUG> // 0);
    put-flushed "Using {$universe ?? "universe '$universe'" !! 'internal stub universe'}.\n";
    my $mugs-server = $universe ?? create-universe-mugs-server($universe)
                                !! create-stub-mugs-server;

    load-plugins('server', $mugs-server);

    put-flushed 'Starting WebSocket server.';
    my $application = routes(:$mugs-server);
    my $ws-server   = create-cro-server(:$application, :$host, :$port,
                                        :$secure, :$private-key-file,
                                        :$certificate-file);

    $ws-server.start;
    my $root = $application.handlers[0].implementation.signature.params[0].constraint_list[0];
    my $url  = "ws{'s' if $secure}://$host:$port/$root";
    put-flushed "Listening at $url\n";

    react {
        whenever signal(SIGINT) {
            put-flushed 'Shutting down.';
            $ws-server.stop;
            done;
        }
    }
}
