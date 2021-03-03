[![Actions Status](https://github.com/Raku-MUGS/MUGS-Core/workflows/test/badge.svg)](https://github.com/Raku-MUGS/MUGS-Core/actions)

NAME
====

MUGS-Core - Core modules for MUGS (Multi-User Gaming Services)

SYNOPSIS
========

    # Setting up a simple MUGS-Core development environment
    mkdir MUGS
    cd MUGS
    git clone git@github.com:Raku-MUGS/MUGS-Core.git
    cd MUGS-Core
    zef install --deps-only .
    raku -Ilib bin/mugs-admin create-universe

DESCRIPTION
===========

**NOTE: See the [top-level MUGS repo](https://github.com/Raku-MUGS/MUGS) for more info.**

MUGS-Core is the core of MUGS (Multi-User Gaming Services), a Raku-based platform for game service development. In other words, it is a set of basic services written in the Raku language for creating client-server and multi-user games. It abstracts away the boilerplate of managing player identities, tracking active games and sessions, sending and receiving messages and actions, and so forth.

This Proof-of-Concept release includes a WebSocket-based game server, simple admin and developer tools, and simple "games" intended primarily for testing. The game server can store data using either an internal ephemeral/test storage driver, or in SQLite databases on disk using a storage driver based on the Red ORM.

ROADMAP
=======

MUGS is still in its infancy, at the beginning of a long and hopefully very enjoyable journey. There is a [draft roadmap for the first few major releases](https://github.com/Raku-MUGS/MUGS/tree/main/docs/todo/release-roadmap.md) but I don't plan to do it all myself -- I'm looking for contributions of all sorts to help make it a reality.

CONTRIBUTING
============

Please do! :-)

In all seriousness, check out [the CONTRIBUTING doc](docs/CONTRIBUTING.md) (identical in each repo) for details on how to contribute, as well as [the Coding Standards doc](https://github.com/Raku-MUGS/MUGS/tree/main/docs/design/coding-standards.md) for guidelines/standards/rules that apply to code contributions in particular.

The MUGS project has a matching GitHub org, [Raku-MUGS](https://github.com/Raku-MUGS), where you will find all related repositories and issue trackers, as well as formal meta-discussion.

More informal discussion can be found on IRC in [Freenode #mugs](ircs://chat.freenode.net:6697/mugs).

AUTHOR
======

Geoffrey Broadwell <gjb@sonic.net> (japhb on GitHub and Freenode)

COPYRIGHT AND LICENSE
=====================

Copyright 2021 Geoffrey Broadwell

MUGS is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

