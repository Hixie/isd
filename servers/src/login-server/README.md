# Protocol

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


## `new`

No other fields.

Server returns the following fields:

 * username
 * password
 * dynasty server URL
 * access token for dynasty server


## `login`

Fields:

 * username
 * password

Server returns the following fields:

 * dynasty server URL
 * access token


## `logout`

Fields:

 * username
 * password

Server returns no additional data.


## `change-username`

Fields:

 * username
 * password
 * new username

Server returns no additional data.


## `change-password`

Fields:

 * username
 * password
 * new password

Server returns no additional data.


## `get-stars`

No other fields.

Server returns one numeric field, whose value is 1. The server will
then at some point send a binary frame whose first 32 bytes form the
little-endian number 1.


## Binary frames

The server sends raw data as binary frames. The binary frames start
with a 32 bit little-endian file identifier, then the rest of the
frame is the raw data of that file.

File identifiers:

 * 1: `stars.dat`, the galaxy.


## Galaxy format

The `stars.dat` file consists of little-endian 32 bit integers:

 * Integer 0: the number of star categories, N.
 * Integer 1..N: the number of stars in each category, M0, M1, M2, etc.
 * Integer N+1..N+M0: the stars in category 0.
 * Integer N+M0+1..N+M0+M1: the stars in category 1.
 * etc.

The categories of astronomical objects (with their color and relative magnitudes) are:

  1. Remote galaxies. 0x7FFFFFFF, 0.0040, blurred.
  2. Remote galaxies. 0xCFCCBBAA, 0.0025.
  3. Red stars. 0xDFFF0000, 0.0005,
  4. Orange stars. 0xCFFF9900, 0.0007,
  5. White stars. 0xBFFFFFFF, 0.0005,
  6. White stars. 0xAFFFFFFF, 0.0012,
  7. Blue stars. 0x2F0099FF, 0.0010,
  8. Bright blue stars. 0x2F0000FF, 0.0005,
  9. Orange stars. 0x4FFF9900, 0.0005,
 10. White stars. 0x2FFFFFFF, 0.0005,
 11. Nebulae. 0x5FFF2200, 0.0200, blurred.
