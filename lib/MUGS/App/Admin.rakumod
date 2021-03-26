# ABSTRACT: Admin tasks (universe, DB, and server management)

use MUGS::Util::File;
use MUGS::Authentication;
use MUGS::Universe;
use MUGS::Server::Universe;


# Use subcommand MAIN args
%PROCESS::SUB-MAIN-OPTS = :named-anywhere;


#| Writeable universe config
class MUGS::Universe::Config::Admin is MUGS::Universe::Config {
    #| Write the universe config to a config file on disk
    method to-file(IO:D() $universe-config-file, Int() $mode = 0o400) {
        my %struct := hash(:$.desc, :$.storage-driver, :$.database, :@.meta-admins);
        write-yaml-file('universe config', $universe-config-file, %struct, :$mode);
    }
}


#| Manage universe trees and the files within them
class MUGS::Universe::Admin is MUGS::Universe {
    #| Default config class
    method default-config-class { MUGS::Universe::Config::Admin }

    #| Die if the universe already exists
    method ensure-new() {
        if $.universe-dir.e {
            note "Universe '$.universe-name' already exists.";
            exit 1;
        }
    }

    #| Create the universe's base directory
    method create-dir(Int() $mode = 0o750) {
        self.ensure-new;
        $.universe-dir.mkdir(:$mode);
    }

    #| Create the universe DB and its schema
    method create-db() {
        $.identity-store.schema-bootstrap;
    }

    #| Create the base admin account, and its owning meta-admin user
    method create-meta-admin() {
        # Create first account
        my $account  = $.identity-store.new-account;

        # Create all meta-admin users in the first account
        for $.universe-config.meta-admins -> $username {
            my $user = $.identity-store.new-user(:$username, :$account);
            # REQUEST_META_ADMIN grant is implied by being in meta-admins list
            # XXXX: Grant REQUEST_SINGLE_ACCOUNT_META_ADMIN(base account)
            # XXXX: Set initial credential
            # XXXX: HERE
        }
    }

    #| Write the current universe config to disk
    method write-config() {
        $.universe-config.to-file($.universe-config-file);
    }

    #| Configure and create a new universe
    method create(*%config) {
        # Configure the universe-to-be
        self.init-config(|%config);

        # Create the universe in stages, writing the config file last
        self.create-dir;
        self.attach-to-database;
        self.create-db;
        self.create-meta-admin;
        self.write-config;
    }
}


#| Create a new MUGS universe (identity namespace)
multi MAIN('create-universe',
           Str:D $universe-name    = 'default',
           Str:D :$desc            = $universe-name,
           Str:D :$storage-driver  = 'Red::SQLite',
           Str:D :$database        = 'mugs-user.sqlite3',
           Str:D :$meta-admin-name = 'meta-admin',
          ) is export {
    my $universe = MUGS::Universe::Admin.new(:$universe-name);
    $universe.create(:$desc, :$storage-driver, :$database,
                     :meta-admins($meta-admin-name,));
    $universe.ensure-valid;

    say "Universe '$universe-name' created successfully in $universe.universe-root()";
}


#| Add TEST identities to an existing MUGS universe
multi MAIN('add-test-identities',
           Str:D $universe-name = 'default',
          ) is export {
    my $universe = MUGS::Universe::Admin.new(:$universe-name);
    unless $universe.exists {
        note qq:to/MISSING/;

            Universe '$universe-name' does not yet exist; you can create it using:

                mugs-admin create-universe $universe-name
            MISSING
        exit 1;
    }

    $universe.ensure-valid;

    my $server = create-universe-mugs-server($universe);
    my $user   = $server.create-account-owner(:username<dakota>, :password<d>);

    say "Test data created in universe '$universe-name' identity database";
}
