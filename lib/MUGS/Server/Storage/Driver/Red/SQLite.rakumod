# ABSTRACT: Red+SQLite persistent server storage driver

unit module MUGS::Server::Storage::Driver::Red::SQLite;

use MUGS::Authentication;
use MUGS::Server::Storage::Identities;
use MUGS::Server::Storage::Credentials;
use MUGS::Server::Storage::Driver::Red::SQLite::IdentitySchema;

use DBIish;
use Red;


#| Identity and credential storage for a server, Red+SQLite driver
class Identities
 does MUGS::Server::Storage::Identities
 does MUGS::Server::Storage::Credentials {
    has Str:D $.database = ':memory:';
    has       $!dbh;


    ### SETUP

    submethod TWEAK() {
        $GLOBAL::RED-DEBUG //= ?$*DEBUG;
        self.connect-to-sqlite;
    }

    method connect-to-sqlite() {
        $!dbh = DBIish.connect('SQLite', :$.database, :RaiseError);
        $!dbh.do('PRAGMA foreign_keys = ON;');
        # XXXX: Scoped?
        $GLOBAL::RED-DB = database('SQLite', $!dbh);
    }

    # XXXX: What about schema updates?
    method create-tables() {
        # XXXX: Transaction wrap?
        my @models = Account, User, Persona, Character, AuthorizedUser, Credential;
        .^create-table(:unless-exists) for @models;
    }


    ### IDENTITIES

    # Create: New identities
    method new-account(::?CLASS:D:) {
        Account.^create;
    }

    method new-user(::?CLASS:D: Str:D :$username!, Account:D :$account!) {
        User.^create(:$username, :$account);
    }
    method new-persona(::?CLASS:D: Str:D :$screen-name!, Account:D :$account!) {
        Persona.^create(:$screen-name, :$account);
    }
    method new-character(::?CLASS:D: Str:D :$screen-name!, Persona:D :$persona!) {
        Character.^create(:$screen-name, :$persona);
    }

    # Read: Point queries by unique keys
    method user-by-name(::?CLASS:D: Str:D $username) {
        User.^load(:$username)
    }
    method persona-by-name(::?CLASS:D: Str:D $screen-name) {
        Persona.^load(:$screen-name)
    }
    method character-by-name(::?CLASS:D: Str:D $screen-name) {
        Character.^load(:$screen-name)
    }


    ### CREDENTIALS

    # Util: inflation helper
    method inflate-credential(Credential:D $credential) {
        # XXXX: What if implementation class unknown?
        my $class = MUGS::Authentication.implementation-class($credential.auth-type);
        $class.from-blob($credential.data-blob, :enabled($credential.enabled))
    }

    # Create: Add a credential for a user
    method add-credential(::?CLASS:D: Str:D :$username,
                          MUGS::Authentication::Credential:D :$credential) {
        # XXXX: What about transaction management?
        my $user      = User.^load(:$username) or self.invalid-username($username);
        my $auth-type = $credential.auth-type;
        my $data-blob = $credential.to-blob;
        Credential.^create(:user-id($user.id), :enabled, :$auth-type, :$data-blob)
    }

    # Read: Queries by username
    multi method credentials-for-username(::?CLASS:D: Str:D $username,
                                          Str:D :$auth-type!) {
        my @creds = Credential.^all.grep({ .user.username eq $username && .enabled.so
                                           && .auth-type eq $auth-type });
        @creds.map: { self.inflate-credential($_) }
    }

    multi method credentials-for-username(::?CLASS:D: Str:D $username) {
        my @creds = Credential.^all.grep({ .user.username eq $username && .enabled.so });
        @creds.map: { self.inflate-credential($_) }
    }
}
