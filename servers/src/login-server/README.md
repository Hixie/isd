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


## `get-constants`

No other fields.

Server returns the following fields:

 * a floating point number representing the diameter of the
   galaxy in meters.


## `get-file`

Fields:

 * file code (integer)

The server will send a binary frame whose first 32 bytes form the
given code as a little-endian number, and whose subsequent bytes are
as described in the "Binary frames" section below.

Then, the server will respond to the original message with no
additional data.


## Binary frames

The server sends raw data as binary frames. The binary frames start
with a 32 bit little-endian file identifier, then the rest of the
frame is the raw data of that file.

File identifiers:

 * 1: `stars.dat`, the galaxy.
 * 2: `systems.dart`, the multiple star systems map.


## Galaxy (file 1)

The file with code 1 consists of little-endian 32 bit integers:

 * Integer 0: the number of star categories, N.
 * Integer 1..N: the number of stars in each category, M0, M1, M2, etc.
 * Integer N+1..N+M0: the stars in category 0.
 * Integer N+M0+1..N+M0+M1: the stars in category 1.
 * etc.

The categories of astronomical objects (with their color and diameters
in meters) are:

  0. Remote galaxies. 0x7FFFFFFF, 4.0e9m, blurred.
  1. Remote galaxies. 0xCFCCBBAA, 2.5e9m.
  2. Red stars. 0xDFFF0000, 0.5e9m,
  3. Orange stars. 0xCFFF9900, 0.7e9m,
  4. White stars. 0xBFFFFFFF, 0.5e9m,
  5. White stars. 0xAFFFFFFF, 1.2e9m,
  6. Blue stars. 0x2F0099FF, 1.0e9m,
  7. Bright blue stars. 0x2F0000FF, 0.5e9m,
  8. Orange stars. 0x4FFF9900, 0.5e9m,
  9. White stars. 0x2FFFFFFF, 0.5e9m,
 10. Red giants. 0x5FFF2200, 20.0e9m, blurred.

The larger objects (marked "blurred") are canonically rendered more
softly than the other stars at scales where all the stars are visible.


## Canonical systems (file 2)

The file with code 2 consists of pairs of little-endian 32 bit
integers represent star IDs. The first of each pair is a star's ID,
and the second is the star ID of the primary star of that first star's
system. The whole file is sorted.

Stars are entries in the galaxy file (with code 1). Star IDs are
formed by shifting the category ID left by 20 bits, and adding the
offset into the category for the star.
