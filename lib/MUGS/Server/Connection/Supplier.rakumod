# ABSTRACT: Server side of in-memory Supplier-based Connection

use MUGS::Message;
use MUGS::Connection;


#| Server side of an in-memory Connection based on Supplier/Supply pairs
class MUGS::Server::Connection::Supplier does MUGS::Server::Connection {
    has $.client-conn is required;
    has $!to-server   = Supplier::Preserving.new;
    has $!from-client = $!to-server.Supply;
    has $!debug       = ?$*DEBUG;

    method disconnect() {
        put "server disconnecting ..." if $!debug;
        # .disconnect with $!client-conn;
        $!client-conn = Nil;
        $!to-server.done;
        put "server disconnected" if $!debug;
    }

    method send-to-client(MUGS::Message:D $message) {
        put "server --> CLIENT:\n{$message.to-json}\n" if $!debug;
        $!client-conn.send-to-client($message);
    }

    method send-to-server(MUGS::Message:D $message) {
        put "server --> SERVER:\n{$message.to-struct.raku.indent(4)}\n" if $!debug;
        $!to-server.emit($message);
    }

    method from-client-supply() { $!from-client }
}
