# ABSTRACT: Abstract roles implemented by connection transports

use MUGS::Message;


#| Base class for connection exceptions
class X::MUGS::Connection is X::MUGS { }

#| Unable to connect to server
class X::MUGS::Connection::Can'tConnect is X::MUGS::Connection {
    has $.server is required;

    method message { "Can't connect to server" }
}


#| An abstraction for the CLIENT side of a client-server connection, hiding
#| details of wire protocol, serialization, compression, encryption, etc.
role MUGS::Client::Connection {
    method connect-to-server                        { ... }
    method disconnect()                             { ... }
    method send-to-server(MUGS::Message:D $message) { ... }
    method from-server-supply()                     { ... }
}


#| An abstraction for the SERVER side of a client-server connection, hiding
#| details of wire protocol, serialization, compression, encryption, etc.
role MUGS::Server::Connection {
    method disconnect()                             { ... }
    method send-to-client(MUGS::Message:D $message) { ... }
    method from-client-supply()                     { ... }
}
