# ABSTRACT: Log::Timeline task/event schema for MUGS::Server

unit module MUGS::Server::LogTimelineSchema;
use Log::Timeline;


class ServerLoading      does Log::Timeline::Event['MUGS', 'Server Core', 'Server Loading'] { }
class ServerInitialized  does Log::Timeline::Event['MUGS', 'Server Core', 'Server Initialized'] { }
class ServerExiting      does Log::Timeline::Event['MUGS', 'Server Core', 'Server Exiting'] { }

class ConnectionAccepted does Log::Timeline::Event['MUGS', 'Server Core', 'Connection Accepted'] { }
class ConnectionDropped  does Log::Timeline::Event['MUGS', 'Server Core', 'Connection Dropped'] { }

class UserAuthSuccess does Log::Timeline::Event['MUGS', 'Server Core', 'User Auth Success'] { }
class UserAuthFailure does Log::Timeline::Event['MUGS', 'Server Core', 'User Auth Failure'] { }

class GameCreated does Log::Timeline::Event['MUGS', 'Server Core', 'Game Created'] { }


# class Bar does Log::Timeline::Task['MUGS', 'Server Core', 'Bar'] { }


# Make sure the timeline starts at process init, not just whenever the server started
INIT with PROCESS::<$LOG-TIMELINE-OUTPUT> {
    .log-event(ServerLoading, 0, $*INIT-INSTANT, {});
}

# Note process end as well
END with PROCESS::<$LOG-TIMELINE-OUTPUT> {
    .log-event(ServerExiting, 0, now, {});
}
