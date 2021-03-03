# ABSTRACT: Server instance using an existing identity universe

use MUGS::Server;
use MUGS::Universe;


#| Create a MUGS::Server instance for an existing identity universe
multi create-universe-mugs-server(MUGS::Universe:D $universe) is export {
    $universe.load-config;
    $universe.attach-to-database;

    my $identity-store   = $universe.identity-store;
    my $credential-store = $identity-store;

    my $server = MUGS::Server.new(:$identity-store, :$credential-store);
    MUGS::Server::LogTimelineSchema::ServerInitialized.log;
    $server
}

#| Create a MUGS::Server instance for an existing identity universe by name
multi create-universe-mugs-server(Str:D $universe-name = 'default') is export {
    my $universe = MUGS::Universe.new(:$universe-name);
    unless $universe.exists {
        note qq:to/MISSING/;

            Universe '$universe-name' does not yet exist; you can create it using:

                mugs-admin create-universe $universe-name

            You may also use an in-memory test universe by calling this program
            with the option --universe='' .
            MISSING
        exit 1;
    }

    create-universe-mugs-server($universe);
}
