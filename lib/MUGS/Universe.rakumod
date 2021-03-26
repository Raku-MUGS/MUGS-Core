# ABSTRACT: Configuration and validation of universes (identity namespaces)

use MUGS::Util::File;
use MUGS::Util::StructureValidator;


#| Keep track of contents of a universe config
class MUGS::Universe::Config {
    has Str:D $.desc           is required;
    has Str:D $.storage-driver is required;
    has Str:D $.database       is required;

    has @.meta-admins;

    #| Load a universe config from a config file; throws an exception if unable
    method from-file(IO:D() $universe-config-file) {
        constant %schema = desc           => Str,
                           storage-driver => Str,
                           database       => Str,
                           meta-admins    => [ Str ];

        my $contents = load-yaml-file('universe config', $universe-config-file);
        validate-structure('universe config file', $contents, %schema);
        self.new(|hash($contents{%schema.keys}:p))
    }
}


#| Load and validate universes
class MUGS::Universe {
    has Str:D $.universe-name        is required;
    has IO:D  $.universe-root        = $*HOME.child('.mugs').child('universes');
    has IO    $.universe-dir         is built(False);
    has IO    $.universe-config-file is built(False);

    has MUGS::Universe::Config $.config-class    = self.default-config-class;
    has MUGS::Universe::Config $.universe-config is built(False);

    has $.identity-store is built(False);


    #| Validate the universe name syntax and configure directory locations
    submethod TWEAK() {
        die "Universe name is invalid; must be a simple identifier."
            unless $!universe-name ~~ /^ \w+ $/;

        $!universe-dir         = $!universe-root.child($!universe-name);
        $!universe-config-file = $!universe-dir .child('universe.yaml');
    }

    #| Check whether a universe with this name already exists
    method exists() {
        $!universe-config-file.r
    }

    #| Default config class
    method default-config-class { MUGS::Universe::Config }

    #| Initialize a new universe config (but don't write it anywhere yet)
    method init-config(*%config) {
        $!universe-config = $.config-class.new(|%config);
    }

    #| Load a universe config from (an already existing) universe directory
    method load-config() {
        $!universe-config = $.config-class.from-file($.universe-config-file);
    }

    #| Load a storage driver by short name
    multi method load-storage-driver($storage-driver) {
        die "Configured storage-driver has wrong format."
            unless $storage-driver ~~ Str:D
                && $storage-driver ~~ /^ [<[A..Z]> \w*]+ % '::' $/;

        my $driver = 'MUGS::Server::Storage::Driver::' ~ $storage-driver;
        try require ::($driver);
        my $package = ::($driver);
        die "Could not load storage driver '$storage-driver' ($driver)"
            if $package ~~ Failure;
        $package
    }

    #| Load the storage driver needed to access the DB
    multi method load-storage-driver() {
        self.load-storage-driver($.universe-config.storage-driver);
    }

    #| Find absolute path to config's DB file
    multi method database-file(MUGS::Universe::Config:D $config) {
        $config.database.IO.absolute($.universe-dir)
    }

    #| Find absolute path to DB file
    multi method database-file() {
        self.database-file($.universe-config);
    }

    #| Attach storage drivers to a database
    multi method attach-to-database(MUGS::Universe::Config:D $config) {
        my $driver-package = self.load-storage-driver($config.storage-driver);
        my $database       = self.database-file($config);

        $!identity-store   = $driver-package.WHO<Identities>.new(:$database);
    }

    #| Attach storage drivers to a database
    multi method attach-to-database() {
        my $driver-package = self.load-storage-driver;
        my $database       = self.database-file;

        $!identity-store   = $driver-package.WHO<Identities>.new(:$database);
    }

    #| Introspect universe DB schema version and state
    method db-schema-info() {
        my %info = $!identity-store.schema-version;
        %info<expected-version> = $!identity-store.schema-expected-version;
        %info
    }

    #| Die unless the universe has a valid directory structure and config file
    method ensure-config-valid() {
        die "Universe dir '$.universe-dir' for universe '$.universe-name' does not exist."
            unless $!universe-dir.e;
        die "Universe dir '$.universe-dir' for universe '$.universe-name' is not readable."
            unless $!universe-dir.r;
        die "Universe dir '$.universe-dir' for universe '$.universe-name' is not accessible (executable)."
            unless $!universe-dir.x;

        die "Universe config file for universe '$.universe-name' does not exist."
            unless $!universe-config-file.e;
        die "Universe config file for universe '$.universe-name' is not readable."
            unless $!universe-config-file.r;
        die "Universe config file for universe '$.universe-name' is writeable."
            if     $!universe-config-file.w;

        my $config   = MUGS::Universe::Config.from-file($!universe-config-file);
        my $package  = self.load-storage-driver($config.storage-driver);

        my $database = self.database-file($config).IO;
        die "Database does not exist."  unless $database.e;
        die "Database is not readable." unless $database.r;
    }

    #| Die unless the universe has a self-consistent DB with an up to date schema
    method ensure-db-consistent() {
        # Check schema state metadata
        my %info = self.db-schema-info;
        die "Universe DB for universe '$.universe-name' is in unexpected state '%info<state>'"
            unless %info<state> eq 'ready';
        die "Universe DB for universe '$.universe-name' has version %info<version>, but expected %info<expected-version> instead"
            unless %info<version> eq %info<expected-version>;

        # XXXX: Check schema
        # XXXX: Check meta-admins exist in user tables
        # XXXX: Check at least one meta-admin has login credentials
        # XXXX: Check all users are associated with an account
    }

    #| Ensure an existing universe is valid and its DB is consistent
    method ensure-valid() {
        self.ensure-config-valid;
        self.ensure-db-consistent;
    }
}
