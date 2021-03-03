# ABSTRACT: Backing storage for server-side identities

use MUGS::Message;
use MUGS::Identity;


#| Identity storage for a server
role MUGS::Server::Storage::Identities {
    # Create: New identities
    method new-account(::?CLASS:D:) { ... }
    method new-user(::?CLASS:D: Str:D :$username!, MUGS::Account:D :$account!) { ... }
    method new-persona(::?CLASS:D: Str:D :$screen-name!, MUGS::Account:D :$account!) { ... }
    method new-character(::?CLASS:D: Str:D :$screen-name!, MUGS::Persona:D :$persona!) { ... }

    # Read: Point queries by unique keys
    method user-by-name(::?CLASS:D: Str:D $username) { ... }
    method persona-by-name(::?CLASS:D: Str:D $screen-name) { ... }
    method character-by-name(::?CLASS:D: Str:D $screen-name) { ... }

    # Exception helpers
    method invalid-username(Str:D $username) {
        X::MUGS::Message::InvalidEntity.new(:type('username'), :id($username)).throw;
    }
    method invalid-persona(Str:D $screen-name) {
        X::MUGS::Message::InvalidEntity.new(:type('persona'), :id($screen-name)).throw;
    }
    method invalid-character(Str:D $screen-name) {
        X::MUGS::Message::InvalidEntity.new(:type('character'), :id($screen-name)).throw;
    }
}
