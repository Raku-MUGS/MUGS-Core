use MUGS::Server;
use MUGS::Server::Connection::WebSocket;

use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;
use Cro::CBOR;


sub routes(MUGS::Server:D :$mugs-server) is export {
    route {
        get -> 'mugs-ws' {
            web-socket :cbor, -> $client-conn, $closed-promise {
                my $connection = MUGS::Server::Connection::WebSocket.new(:$client-conn,
                                                                         :$closed-promise);
                $mugs-server.accept-connection(:$connection).from-server;
            }
        }
    }
}
