# ABSTRACT: Client side of in-memory Supplier-based Connection

use CBOR::Simple;

use MUGS::Message;
use MUGS::Connection;
use MUGS::Server::Connection::Supplier;


#| Client side of an in-memory Connection based on Supplier/Supply pairs
class MUGS::Client::Connection::Supplier does MUGS::Client::Connection {
    has $!server-conn;
    has $!to-client   = Supplier::Preserving.new;
    has $!from-server = $!to-client.Supply;
    has $!debug       = ?$*DEBUG;

    method connect-to-server(::?CLASS:D: :$server!) {
        put "client connecting to '$server' ..." if $!debug;
        my $connection = MUGS::Server::Connection::Supplier.new(:client-conn(self));
        $!server-conn = $server.accept-connection(:$connection)
            or X::MUGS::Connection::Can'tConnect.new(:$server).throw;
        put "client successfully connected to '$server'" if $!debug;
    }

    method disconnect() {
        put "client disconnecting ..." if $!debug;
        .disconnect with $!server-conn;
        $!server-conn = Nil;
        $!to-client.done;
        put "client disconnected" if $!debug;
    }

    method send-to-client(Blob:D $cbor) {
        my $struct = cbor-decode $cbor;
        put "client --> CLIENT:\n{$struct.raku.indent(4)}\n" if $!debug;

        $!to-client.emit:
            $struct<request-id> ?? MUGS::Message::Response.from-struct($struct) !!
            $struct<pack>       ?? MUGS::Message::PushPack.from-struct($struct) !!
                                   MUGS::Message::Push.from-struct($struct)
    }

    method send-to-server(MUGS::Message:D $message) {
        put "client --> SERVER:\n{$message.to-debug}\n" if $!debug;
        $!server-conn.send-to-server($message.to-cbor);
    }

    method from-server-supply() { $!from-server }
}
