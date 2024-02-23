# ABSTRACT: Client side of WebSocket-based Connection

use MUGS::Message;
use MUGS::Connection;

use Cro::WebSocket::Message;
use Cro::WebSocket::Client;
use Cro::CBOR;
use JSON::Fast;


#| A WebSocket Connection to an independent MUGS server
class MUGS::Client::Connection::WebSocket does MUGS::Client::Connection {
    has $!cro-client;
    has $!server-conn;
    has $!debug = $*DEBUG // 0;

    method connect-to-server(::?CLASS:D: :$server!, :%ca) {
        note "client connecting to '$server' ..." if $!debug;
        $!cro-client  = Cro::CBOR::WebSocket::Client.new(:uri($server), :cbor);
        $!server-conn = await $!cro-client.connect(:%ca);
        note "client successfully connected to '$server'" if $!debug;
    }

    method disconnect() {
        note "client disconnecting ..." if $!debug;
        await .close with $!server-conn;
        note "client disconnected" if $!debug;
    }

    method send-to-server(MUGS::Message:D $message) {
        my $struct = $message.to-struct;
        note "client --> SERVER:\n{ to-json $struct, :sorted-keys }\n" if $!debug >= 2;
        $!server-conn.send: Cro::WebSocket::Message.new(:!fragmented,
                                                        :body($struct));
    }

    method from-server-supply() {
        supply whenever $!server-conn.messages -> $message {
            whenever $message.body -> $struct {
                note "From server:\n{ to-json $struct, :sorted-keys }\n" if $!debug >= 2;
                emit $struct<request-id> ?? MUGS::Message::Response.from-struct($struct) !!
                     $struct<pack>       ?? MUGS::Message::PushPack.from-struct($struct) !!
                                            MUGS::Message::Push.from-struct($struct)
            }
        }
    }
}
