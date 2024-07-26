# Public Protocol

## Public commands

Commands are sent from the client to the server in the form of
WebSocket text frames whose format is null-terminated fields of UTF-8.

The first field is the command, the second is a 32 bit number called
the conversation ID.

The server responds in the same format. Replies always start with a
field that says `reply`, then the conversation ID, then either a `T`
if the command was successful, followed by some extra data as
described below, or an `F` indicating failure, followed by an error
code from the list in `../common/isderrors.pas`.

Replies are not guaranteed to be sent back in the order that messages
were received (hence the conversation ID field).


### `login`

Fields:

 * Access token from login server's `login` message

Response:

 * A number that is the user's globally unique dynasty ID.
 * Count of system servers
 * URL for each system server


### `get-star-name`

Does not require being logged in.

Fields:

 * a star ID (see "Canonical systems" file format in login server docs)

Server returns the following fields:

 * String, the name of the given star.


## Updates

Occasionally, after receiving a successful `login` command, the server
may send unsolicited messages. These are in a similar form to
commands; WebSocket text frames containing null-terminated fields of
UTF-8. The first field is the message name. No response is expected
from the client.

### `system-servers`

The server may occasionally send a message whose payload is:

 * Count of system servers
 * URL for each system server

This is similar to the response to a `login` command.


# Internal Protocol

Raw TCP, starting with a null, a 4-byte length, a password of that
length, and then 4-byte length-prefixed frames.

Each frame starts with a 4-byte-length-prefixed string, the command.


## `create-account` (`icCreateAccount`)

Fields:

 * dynasty ID (4-byte integer)

Response is one of:

 * 0x01 byte indicating success
 * disconnection indicating failure


## `register-token` (`icRegisterToken`)

Fields:

 * dynasty ID (4-byte integer)
 * 4-byte-length-prefixed salt
 * 4-byte-length-prefixed password hash

Response is one of:

 * 0x01 byte indicating success
 * disconnection indicating failure


## `logout` (`icLogout`)

Fields:

 * dynasty ID (4-byte integer)

Response is one of:

 * 0x01 byte indicating success
 * disconnection indicating failure


## `add-system-server`

Fields:

 * dynasty ID (4-byte integer)
 * system server ID (4-byte integer)

Response is one of:

 * 0x01 byte indicating success
 * disconnection indicating failure


## `remove-system-server`

Fields:

 * dynasty ID (4-byte integer)
 * system server ID (4-byte integer)

Response is one of:

 * 0x01 byte indicating success
 * disconnection indicating failure
