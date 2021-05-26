# ABSTRACT: Core intro docs and global definitions for MUGS

unit class MUGS::Core:auth<zef:japhb>:ver<0.1.2>;


# Type for GameIDs
subset GameID of Int is export;


# Standard statuses
enum Status is export < Success RequestError ResponseError ServerError >;


# Standard game events
enum GameEventType is export < GameCreated GameStarted GamePaused GameEnded
                               CharacterJoined CharacterAction CharacterLeft >;


# Standard game states; states >= Finished must be game over variants.
enum GameState is export < NotStarted Paused InProgress Finished Abandoned >;


# Standard win/loss states; separate from GameState because multiplayer, and
# some games such as mazes and treasure hunts allow someone to "go on to the
# next round" (win or rank) before all players have finished the game.
enum WinLoss is export < Undecided Loss Tie Win Ranked >;


# ID generation
# XXXX: To prevent leaks between sessions, this should be per-session, not per-process
my atomicint $NEXT-ID = 0;
sub term:<NEXT-ID>() is export { ++⚛$NEXT-ID }


# Base class for all MUGS exceptions
class X::MUGS is Exception { }


=begin pod

=head1 NAME

MUGS-Core - Core modules for MUGS (Multi-User Gaming Services)

=head1 SYNOPSIS

  # Setting up a simple MUGS-Core development environment
  mkdir MUGS
  cd MUGS
  git clone git@github.com:Raku-MUGS/MUGS-Core.git
  cd MUGS-Core
  zef install --deps-only --exclude="pq:ver<5>:from<native>" .
  raku -Ilib bin/mugs-admin create-universe


=head1 DESCRIPTION

B<NOTE: See the L<top-level MUGS repo|https://github.com/Raku-MUGS/MUGS> for more info.>

MUGS-Core is the core of MUGS (Multi-User Gaming Services), a Raku-based
platform for game service development.  In other words, it is a set of basic
services written in the Raku language for creating client-server and multi-user
games.  It abstracts away the boilerplate of managing player identities,
tracking active games and sessions, sending and receiving messages and actions,
and so forth.

This Proof-of-Concept release includes a WebSocket-based game server, simple
admin and developer tools, and simple "games" intended primarily for testing.
The game server can store data using either an internal ephemeral/test storage
driver, or in SQLite databases on disk using a storage driver based on the Red
ORM.


=head1 ROADMAP

MUGS is still in its infancy, at the beginning of a long and hopefully very
enjoyable journey.  There is a
L<draft roadmap for the first few major releases|https://github.com/Raku-MUGS/MUGS/tree/main/docs/todo/release-roadmap.md>
but I don't plan to do it all myself -- I'm looking for contributions of all
sorts to help make it a reality.


=head1 CONTRIBUTING

Please do!  :-)

In all seriousness, check out L<the CONTRIBUTING doc|docs/CONTRIBUTING.md>
(identical in each repo) for details on how to contribute, as well as
L<the Coding Standards doc|https://github.com/Raku-MUGS/MUGS/tree/main/docs/design/coding-standards.md>
for guidelines/standards/rules that apply to code contributions in particular.

The MUGS project has a matching GitHub org,
L<Raku-MUGS|https://github.com/Raku-MUGS>, where you will find all related
repositories and issue trackers, as well as formal meta-discussion.

More informal discussion can be found on IRC in
L<Libera.Chat #mugs|ircs://irc.libera.chat:6697/mugs>.


=head1 AUTHOR

Geoffrey Broadwell <gjb@sonic.net> (japhb on GitHub and Libera.Chat)


=head1 COPYRIGHT AND LICENSE

Copyright 2021 Geoffrey Broadwell

MUGS is free software; you can redistribute it and/or modify it under the
Artistic License 2.0.

=end pod
