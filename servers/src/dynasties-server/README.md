# Public Protocol

## Public commands

See the README.md in the parent directory for context.

### `login`

Fields:

 * Access token from login server's `login` message

Response:

 * A number that is the user's globally unique dynasty ID (uint64).
 * Count of system servers (uint64).
 * URL for each system server.


### `get-star-name`

Does not require being logged in.

Fields:

 * a star ID (see "Canonical systems" file format in login server docs).

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

 * Count of system servers (uint64).
 * URL for each system server.

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
