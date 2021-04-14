# ABSTRACT: Server side of WebSocket-based Connection

use MUGS::Message;
use MUGS::Connection;

use JSON::Fast;


#| A Connection served over a WebSocket
class MUGS::Server::Connection::WebSocket does MUGS::Server::Connection {
    has $.client-conn    is required;
    has $.closed-promise is required;
    has $!to-client   = Supplier::Preserving.new;
    has $.from-server = $!to-client.Supply;
    has $!debug       = ?$*DEBUG;

    method disconnect() {
        put "server disconnecting from '$.debug-name'..." if $!debug;
        # .close with $!client-conn;
        $!client-conn = Nil;
        $!to-client.done;
        put "server disconnected from '$.debug-name'" if $!debug;
    }

    method send-to-client(MUGS::Message:D $message) {
        my $struct = $message.to-struct;
        put "server --> CLIENT ($.debug-name):\n{ to-json $struct, :sorted-keys }\n" if $!debug;
        $!to-client.emit($struct);
    }

    method from-client-supply() {
        supply whenever $!client-conn -> $message {
            whenever $message.body -> $struct {
                put "From client ($.debug-name):\n{ to-json $struct, :sorted-keys }\n" if $!debug;
                emit $struct<game-id>
                    ?? MUGS::Message::Request::InGame.from-struct($struct)
                    !! MUGS::Message::Request.from-struct($struct);
            }
        }
    }
}
