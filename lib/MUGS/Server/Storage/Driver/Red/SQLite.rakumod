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
        my @models = Identity, Account, User, Persona, Character,
                     AuthorizedUser, Credential;
        .^create-table(:unless-exists) for @models;
    }


    ### SCHEMA MANAGEMENT

    method schema-expected-version() { 1 }

    method schema-table-def(::?CLASS:D: Str:D $table-name) {
        # NOTE: I'd prefer to use sqlite_schema here, but not all sqlite
        #       versions in common use support it
        my $sth = $!dbh.execute('SELECT * FROM sqlite_master WHERE type="table" AND name=?;',
                                $table-name);
        my %def = $sth.row(:hash);
    }

    method schema-version(::?CLASS:D:) {
        # First, check if there is even a mugs_schema_state table at all
        my $found = self.schema-table-def('mugs_schema_state');
        return %( :version(0), :state<no-state-table> ) unless $found;

        # Next, introspect mugs_schema_state to figure out current schema version
        my $sth = $!dbh.prepare('SELECT value FROM mugs_schema_state WHERE key=?;');
        my ($meta_ver) = $sth.execute('schema_state_version').row;
        return %( :version(0), :state<no-state-version> ) unless $meta_ver;
        return %( :version(0), :state<unknown> )          unless $meta_ver == 1;

        my ($version) = $sth.execute('schema_version').row;
        return %( :version(0), :state<no-schema-version> ) unless $version;
        $version = +$version;

        my ($state) = $sth.execute('schema_state').row;
        return %( :$version, :state<no-state> ) unless $state;

        %( :$version, :$state );
    }

    method schema-change-state(::?CLASS:D: :$old-state, :$new-state) {
        $!dbh.execute(q:to/UPDATE_STATE/, $new-state, $old-state);
            UPDATE mugs_schema_state SET value=?
            WHERE  key="schema_state" AND value=?
            UPDATE_STATE
    }

    method schema-bootstrap(::?CLASS:D:) {
        # Bootstrap or fix broken bootstrap
        $!dbh.execute(q:to/CREATE_TABLE/);
            CREATE TABLE IF NOT EXISTS mugs_schema_state (
                id    integer      NOT NULL primary key,
                key   varchar(255) NOT NULL,
                value varchar(255) NOT NULL,
                UNIQUE (key)
            );
            CREATE_TABLE

        my $sth = $!dbh.prepare(q:to/INSERT_OR_IGNORE/);
            INSERT OR IGNORE INTO mugs_schema_state
            (key, value)
            VALUES (?,?);
            INSERT_OR_IGNORE
        $sth.execute('schema_state_version', '1');
        $sth.execute('schema_version',       '1');
        $sth.execute('schema_state',         'bootstrapping');

        self.create-tables;
        self.schema-change-state(:old-state('bootstrapping'),
                                 :new-state('ready'));
    }

    method schema-update(::?CLASS:D:) {
        my %schema-info = self.schema-version;
        given %schema-info<version> {
            when 0 { self.schema-bootstrap }
        }
    }


    ### IDENTITIES

    # Create: New identities
    method new-account(::?CLASS:D:) {
        Account.^create;
    }

    method new-user(::?CLASS:D: Str:D :$username!, Account:D :$account!) {
        self.reserve-name(User, $username);
        User.^create(:$username, :$account);
    }
    method new-persona(::?CLASS:D: Str:D :$screen-name!, Account:D :$account!) {
        self.reserve-name(Persona, $screen-name);
        Persona.^create(:$screen-name, :$account);
    }
    method new-character(::?CLASS:D: Str:D :$screen-name!, Persona:D :$persona!) {
        self.reserve-name(Character, $screen-name);
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
    method identity-by-name(::?CLASS:D: Str:D $name) {
        if self.name-reservation($name) -> $identity {
            given $identity.identity-type {
                when 'User'      { self.user-by-name($identity.name) }
                when 'Persona'   { self.persona-by-name($identity.name) }
                when 'Character' { self.character-by-name($identity.name) }
                default { die "Unknown identity type '$_' in Identity table" }
            }
        }
    }


    # De-confusion: Namespace folding and reservation
    method name-reservation(::?CLASS:D: Str:D $name) {
        my $deconfused = self.fold-name($name);
        Identity.^load(:$deconfused)
    }
    method name-reserved(::?CLASS:D: Str:D $name) {
        self.name-reservation.so;
    }
    method reserve-name(::?CLASS:D: MUGS::Identity:U $identity-type, Str:D $name) {
        my $deconfused = self.fold-name($name);
        Identity.^create(:$deconfused, :$name, :identity-type($identity-type.^name))
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
