# Public Protocol

The servers export an API using WebSockets.

The protocol uses WebSocket text frames containing a list of one or
more null-terminated fields.

There are five kinds of fields:

   - int64: optional "-" prefix, followed by digits representing an
     number in the range -2^63 .. 2^63-1.

   - uint64: digits representing an number in the range 0 .. 2^64-1.

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
     fields unless otherwise specified.

The first field is the command, the second is a 32 bit number called
the conversation ID. Subsequent fields are arguments to the command
and are command-specific.

The server responds in the same format. Replies always start with a
field that says `reply`, then the conversation ID (uint64), then
either a `T` if the command was successful, followed by some extra
data specific to the command, or an `F` indicating failure, followed
by an error code from the list in `common/isderrors.pas`.

Replies are not guaranteed to be sent back in the order that messages
were received (hence the conversation ID field).


# Internal Protocol

Servers talk directly to themselves over the same ports.

These communications do not use WebSockets. Instead, they are
streaming messages over TCP. The conversation starts with a null from
the client to the server, followed by a 4-byte length, and a password
of that length.

The server does not respond to this preamble other than by terminating
the connection on error.

Messages are then sent from the client to the server in 4-byte
length-prefixed frames. Within each frame, data is sent as either
4-byte integers, raw bytes, or 8-byte doubles. Strings are sent by
first sending a 4-byte integer giving the byte length of the string,
then that many raw bytes.

Each frame starts with a string giving the command.

For example, a simple message with one command "x" could be sent as:

    00 00 00 05 00 00 00 01 78
    -+--------- ----------- --
     |          -+------------
     |           |
     |           command
     |
     packet length

The server responds to each command by either sending a single 0x01
byte, or disconnecting.