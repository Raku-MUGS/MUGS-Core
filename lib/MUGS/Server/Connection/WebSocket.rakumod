# ABSTRACT: Server side of WebSocket-based Connection

use MUGS::Message;
use MUGS::Connection;

use JSON::Fast;
use Cro::WebSocket::Message;


#| A Connection served over a WebSocket
class MUGS::Server::Connection::WebSocket does MUGS::Server::Connection {
    has $.client-conn    is required;
    has $.closed-promise is required;
    has $!to-client   = Supplier::Preserving.new;
    has $.from-server = $!to-client.Supply;
    has $!debug       = $*DEBUG // 0;

    method disconnect() {
        put "server disconnecting from '$.debug-name'..." if $!debug;
        # .close with $!client-conn;
        $!client-conn = Nil;
        $!to-client.done;
        put "server disconnected from '$.debug-name'" if $!debug;
    }

    method send-to-client(MUGS::Message:D $message) {
        if $!debug {
            my $t0     = now;
            my $struct = $message.to-struct;

            put "{$t0.DateTime}] server --> CLIENT ($.debug-name):\n{ to-json $struct, :sorted-keys }\n";
            $!to-client.emit: Cro::WebSocket::Message.new(:!fragmented, :body($struct));
        }
        else {
            $!to-client.emit: Cro::WebSocket::Message.new(:!fragmented,
                                                          :body($message.to-struct));
        }
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
