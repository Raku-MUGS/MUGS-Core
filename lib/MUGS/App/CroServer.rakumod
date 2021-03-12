# ABSTRACT: Helper routines to set up and run a Cro server for MUGS

use Cro::HTTP::Log::File;
use Cro::HTTP::Server;


#| Create a Cro::HTTP::Server wrapping the server app
sub create-cro-server(:$application!, Str:D :$host!, UInt:D :$port!,
                      Bool:D :$secure!, :$private-key-file!, :$certificate-file!
                     ) is export {
    my Cro::Service $http = Cro::HTTP::Server.new(
        http => <1.1>, :$host, :$port, :$application,
        |(tls => %( :$private-key-file, :$certificate-file ) if $secure),
        after => [
            Cro::HTTP::Log::File.new(logs => $*OUT, errors => $*ERR)
        ]
    );
}


#| Convenience method to flush a single message to $*OUT without autoflush
sub put-flushed(Str:D $message) is export {
    put $message;
    $*OUT.flush;
}


#| Load plugins for a namespace and display loaded plugins
sub load-plugins(Str:D $type, $loader, |c) is export {
    put-flushed "Loading game $type plugins.";
    $loader.load-game-plugins(|c);
    my @loaded = $loader.known-implementations.sort;
    put-flushed "Loaded: @loaded[]\n";
}
