# ABSTRACT: Stubbed version of server containing only local and test data

use MUGS::Authentication;
use MUGS::Server;


#| A simple game server with test data
class MUGS::Server::WithTestData is MUGS::Server {
    #| Create stubbed identities for tests or a local one-off game
    method create-stub-identities(::?CLASS:D: Str:D :$username!,
                                  Str:D :$password!,
                                  Str:D :$screen-name = $username,
                                  Str:D :$persona-screen-name = $screen-name,
                                  Str:D :$character-screen-name = $screen-name) {
        my $creator   = self.create-account-owner(:$username, :$password);
        my $persona   = self.create-persona(:$creator,
                                            :screen-name($persona-screen-name));
        my $character = self.create-character(:$creator, :$persona,
                                              :screen-name($character-screen-name));
    }

    #| Create minimal fake data needed for a local one-off game
    method populate-minimal-local-data(::?CLASS:D: Bool:D :$include-default-user = True) {
        if $include-default-user {
            self.create-stub-identities: :username<default-user>, :password(''),
                                         :persona-screen-name('Default Persona'),
                                         :character-screen-name('Default Character');
        }
    }

    #| Create fake data needed for tests
    method populate-fake-data(::?CLASS:D: Bool:D :$include-default-user = False) {
        self.populate-minimal-local-data(:$include-default-user);

        self.create-stub-identities: :username<mallory>, :password<m>,
                                     :persona-screen-name('Alice and Bob'),
                                     :character-screen-name<Charlie>;
        self.create-stub-identities: :username<dakota>, :password<d>,
                                     :persona-screen-name<Emerson>,
                                     :character-screen-name<Frankie>;
    }
}


#| Create a MUGS::Server instance with fake/stubbed user data
sub create-stub-mugs-server(Bool:D :$include-default-user = False,
                            Str:D :$storage-driver = 'Fake') is export {
    my $driver = 'MUGS::Server::Storage::Driver::' ~ $storage-driver;
    require ::($driver);

    my ($identity-store, $credential-store);
    given $storage-driver {
        when 'Fake' {
            # XXXX: Next line is a total hack for an apparent Rakudo bug(?) in
            #       which only Credentials exists in ::($driver).WHO after require
            require ::($driver ~ '::Identities');
            $identity-store   = ::($driver).WHO<Identities>.new;
            $credential-store = ::($driver).WHO<Credentials>.new;
        }
        when 'Red::SQLite' {
            # $identity-store = ::($driver).WHO<Identities>.new(:database('mugs-user.sqlite3'));
            $identity-store   = ::($driver).WHO<Identities>.new;
            $credential-store = $identity-store;
            $identity-store.create-tables;
        }
        default {
            die "Unknown storage driver '$storage-driver'";
        }
    }

    my $server = MUGS::Server::WithTestData.new(:$identity-store, :$credential-store);
    $server.populate-fake-data(:$include-default-user);
    MUGS::Server::LogTimelineSchema::ServerInitialized.log;
    $server
}
