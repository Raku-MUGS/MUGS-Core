# ABSTRACT: Client side of WebSocket-based Connection

use MUGS::Message;
use MUGS::Connection;

use Cro::WebSocket::Client;
use Cro::CBOR;
use JSON::Fast;


#| A WebSocket Connection to an independent MUGS server
class MUGS::Client::Connection::WebSocket does MUGS::Client::Connection {
    has $!cro-client;
    has $!server-conn;
    has $!debug = ?$*DEBUG;

    method connect-to-server(::?CLASS:D: :$server!, :%ca) {
        put "client connecting to '$server' ..." if $!debug;
        $!cro-client  = Cro::CBOR::WebSocket::Client.new(:uri($server), :cbor);
        $!server-conn = await $!cro-client.connect(:%ca);
        put "client successfully connected to '$server'" if $!debug;
    }

    method disconnect() {
        put "client disconnecting ..." if $!debug;
        await .close with $!server-conn;
        put "client disconnected" if $!debug;
    }

    method send-to-server(MUGS::Message:D $message) {
        my $struct = $message.to-struct;
        put "client --> SERVER:\n{ to-json $struct, :sorted-keys }\n" if $!debug;
        $!server-conn.send($struct);
    }

    method from-server-supply() {
        supply whenever $!server-conn.messages -> $message {
            whenever $message.body -> $struct {
                put "From server:\n{ to-json $struct, :sorted-keys }\n" if $!debug;
                emit $struct<request-id> ?? MUGS::Message::Response.from-struct($struct)
                                         !! MUGS::Message::Push.from-struct($struct)
            }
        }
    }
}
