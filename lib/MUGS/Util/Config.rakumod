# ABSTRACT: Configuration loaders

use MUGS::Util::File;


#| Base class for config errors
class X::MUGS::Config is X::MUGS { }

#| A structural error in a config file
class X::MUGS::Config::Structure is X::MUGS::Config {
    has Str:D $.message is required;
}


#| Parsed config information and associated defaults
class MUGS::Util::Config {
    has Str:D $.type is required;
    has IO:D  $.config-dir = $*HOME.child('.mugs');

    has %.config;
    has %.defaults;


    #| Retrieve a config value (or its default, if not set)
    method value(Str:D $section, +@keys) {
        my $config  = %!config{$section};
           $config .= AT-KEY($_) for @keys;
           $config // self.default($section, @keys)
    }

    #| Retrieve a config default, ignoring user's config settings
    method default(Str:D $section, +@keys) {
        my $default  = %!defaults{$section};
           $default .= AT-KEY($_) for @keys;
           $default
    }

    #| (Re-)Load defaults for this config $.type, only updating if parseable
    method load-defaults() {
        my $resource = 'conf/' ~ $.type ~ '-defaults.yaml';
        my $defaults = try load-yaml-file("$.type defaults", %?RESOURCES{$resource});
        my @errors   = self!config-errors($!, $defaults);
        %!defaults  := $defaults unless @errors;

        @errors
    }

    #| (Re-)Load the config file if one is found, only updating if parseable
    method load-config-file() {
        my $file    = $.type ~ '-config.yaml';
        my $config  = try load-yaml-file("$.type config", $file, :base-dir($.config-dir));
        my @errors  = self!config-errors($!, $config);
        %!config   := $config unless @errors;

        @errors
    }

    #| Produce a list of basic config errors to present to the user
    method !config-errors($loading-error, $config) {
        return $loading-error if $loading-error;

        my sub structure-error(Str:D $message) {
            X::MUGS::Config::Structure.new(:$message)
        }

        return structure-error("Top level of config is not a map of section names to config sections.")
            unless $config ~~ Map;
        return structure-error("Top level of config has an empty or non-string section name.")
            if $config.keys.grep: { !($_ && $_ ~~ Str) };

        my @non-maps = $config.keys.grep({ $config{$_} !~~ Map }).map:
            { structure-error("Config section '$_' is not a key-value map.") };
        return @non-maps if @non-maps;

        my @empty-keys = $config.keys.grep(-> $key {
            $config{$key}.keys.grep({ !($_ && $_ ~~ Str) }).so
        }).map: { structure-error("Config section '$_' contains an empty or non-string config key.") };
        return @empty-keys if @empty-keys;

        # XXXX: All keys should be ASCII, only [a-zA-Z] + '-'

        return Empty;
    }
}
