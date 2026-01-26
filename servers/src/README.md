# Public Protocol

The servers export an API using WebSockets.

The protocol uses WebSocket text frames containing a list of one or
more null-terminated fields.

There are several kinds of fields:

   - int64: optional "-" prefix, followed by digits representing an
     number in the range -2^63 .. 2^63-1.

   - uint64: digits representing an number in the range 0 .. 2^64-1.

   - int32: same as int64 but the number must be in the range -2^31 ..
     2^31-1.

   - uint32: same as uint64 but the number must be in the range 0 ..
     2^32-1.

   - double: "Nan" for not-a-number, "+Inf" for positive infinity,
     "-Inf" for negative infinity, and otherwise an optional sign,
     followed by digits, a period, and optionally an "E" followed by
     an optional sign and more digits, where the number before the "E"
     is the mantissa and the number after the "E" is an exponent, with
     the range of a IEEE754 binary64. Infinities are never sent by the
     server. Non-numbers and infinities must never be sent by the
     client.

   - boolean: "T" for true, "F" for false.

   - string: plain text (that conforms to UTF-8). All fields are text
     fields unless otherwise specified. Where the protocol
     documentation refers to characters, it means Unicode Scalar
     Values. For example, 🏳️‍🌈 is four characters (U+1F3F3 U+FE0F
     U+200D U+1F308).

The first field is a 32 bit number called the conversation ID
(uint32). The second field is a command (string). Subsequent fields
are arguments to the command and are command-specific.

Missing fields are treated as zero, false, or the empty string, as
appropriate.

The server responds with the same field format. Replies always start
with a field that says `reply`, then the conversation ID (uint32),
then either a `T` if the command was successful, followed by some
extra data specific to the command, or an `F` indicating failure,
followed by an error code from this list:

   'invalid message': message was incorrect in some way. For example,
   sending a `play` message to an asset that is owned by another
   player, with a command that is only valid for player-owned assets,
   will return this (see [systems-server/README.md]). (See also 'not
   owner'.)
   
   'inadequate password': the password did not fulfill the
   requirements described in [login-server/README.md].
   
   'inadequate username': the username did not fulfill the
   requirements described in [login-server/README.md].
   
   'internal error': some error was caught on the server side. This
   does not indicate a client problem. Please report such errors.
   
   'invalid command': the command is not recognized. Only commands
   documented in these README files are known.
   
   'no destructors': a `play`/`dismantle` command (see
   [systems-server/README.md]) was sent to an asset that cannot find a
   destructor (such as a population center), so the asset cannot be
   dismantled. For example, this may happen when trying to dismantle a
   star, unless the player has especially advanced (as yet
   unimplemented) technology.
   
   'not logged in': a command was sent that expects the connection to
   be authenticated, before the `login` command was successfully sent.

   'not owner': a command was sent to an unowned asset, but the
   command is only valid if the asset is owned. See also 'invalid
   message'.
   
   'range error': a command was sent with an argument outside the
   valid range of values (e.g. `set-state` to an `fcFactory` with a
   rate above the maximum rate or below zero).
   
   'unknown dynasty': the specified dynasty is not recognized, for
   example when requesting dynasty scores via `get-scores` (see
   [login-server/README.md]).
   
   'unknown file code': an invalid file code was specified for the
   `get-file` command (see [login-server/README.md]).

   'unrecognized credentials': invalid username or password.

Replies are not guaranteed to be sent back in the order that messages
were received (hence the conversation ID field).

In principle a server can send other messages that are not replies;
the only such example currently is in the systems server, where such
messages use WebSocket binary frames.


# Internal Protocol

Servers talk directly to themselves over the same ports.

These communications do not use WebSockets. Instead, they are
streaming messages over TCP. The conversation starts with a null from
the client to the server, followed by a 4-byte length, and a password
of that length.

The server does not respond to this preamble if the password is
correct; if it is not, the server terminates the connection.

Messages are then sent from the client to the server in
4-byte-length-prefixed frames. Within each frame, data is sent as
either 4-byte integers, raw bytes, or 8-byte doubles. Strings are sent
by first sending a 4-byte integer giving the byte length of the
string, then that many raw bytes. Numbers are sent little-endian.

Each frame starts with a string giving the command.

For example, a simple message with one command "x" could be sent as:

    05 00 00 00 01 00 00 00 78
    -+--------- ----------- --
     |          -+------------
     |           |
     |           command
     |
     packet length

The server responds to each command by either sending a single 0x01
byte, or disconnecting.


## `advance-clock` (`icAdvanceClock`)

Only available in test mode.

Fields:

 * time delta (64-bit integer)

Response is one of:

 * 0x01 byte indicating success
 * disconnection indicating failure

The server's internal clock is advanced by the time delta.
In test mode, the server clock otherwise does not advance.


# TLS configuration

Ports 10024-10030 are forwarded to ports 1024-1030 by the stunnel
configuration in `~/bin/stunnel/etc/stunnel/stunnel.conf` which is run
automatically on server startup (as part of Remy).