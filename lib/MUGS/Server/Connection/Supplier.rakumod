# ABSTRACT: Server side of in-memory Supplier-based Connection

use CBOR::Simple;

use MUGS::Message;
use MUGS::Connection;


#| Server side of an in-memory Connection based on Supplier/Supply pairs
class MUGS::Server::Connection::Supplier does MUGS::Server::Connection {
    has $.client-conn is required;
    has $!to-server   = Supplier::Preserving.new;
    has $!from-client = $!to-server.Supply;
    has $!debug       = $*DEBUG // 0;

    method disconnect() {
        note "server disconnecting ..." if $!debug;
        # .disconnect with $!client-conn;
        $!client-conn = Nil;
        $!to-server.done;
        note "server disconnected" if $!debug;
    }

    method send-to-client(MUGS::Message:D $message) {
        note "server --> CLIENT:\n{$message.to-debug}\n" if $!debug >= 2;
        $!client-conn.send-to-client($message.to-cbor) if $!client-conn;
    }

    method send-to-server(Blob:D $cbor) {
        my $struct = cbor-decode $cbor;
        note "server --> SERVER:\n{$struct.raku.indent(4)}\n" if $!debug >= 2;

        $!to-server.emit: $struct<game-id>
                          ?? MUGS::Message::Request::InGame.from-struct($struct)
                          !! MUGS::Message::Request.from-struct($struct);
    }

    method from-client-supply() { $!from-client }
}
