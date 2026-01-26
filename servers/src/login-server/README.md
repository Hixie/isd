# Protocol

See the README.md in the parent directory for context.

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

Username must be unique, must be between 1 and 127 characters long
(inclusive), and must not contain a U+0010 character.


## `change-password`

Fields:

 * username
 * password
 * new password

Server returns no additional data.

Password must be at least six characters long.


## `get-constants`

No other fields.

Server returns the following fields:

 * a floating point number representing the diameter of the
   galaxy in meters.


## `get-file`

Fields:

 * file code (uint64)

The server will send a binary frame whose first 32 bytes form the
given code as a little-endian number, and whose subsequent bytes are
as described in the "Data files" section below.

Then, the server will respond to the original message with no
additional data.


## `get-high-scores`

Fields:

 * Zero or more dynasty IDs (uint32) to include

This returns the latest 1024 (or fewer) data points for the scores of
the listed dynasties, the currently highest-scoring dynasties, and the
all-time highest scoring dynasties (even if they have since lost that
distinction).

The server will send a binary frame that consists of a zero (uint32)
followed by the following segments, repeated multiple times (once per
dynasty):

 * Dynasty ID (uint32)
 * Index of the last data point being reported for this dynasty (uint32)
 * N: Number of data points (uint32; index or 1024 whichever is smaller)
 * Timestamp (uint64) and score (double), N times.

Then, the server will respond to the original message with no
additional data.


## `get-scores`

Fields:

 * One or more pairs of:
    * Dynasty ID (uint32)
    * Index of last requested datapoint (uint32)

This returns 1024 (or fewer) data points for the scores of the listed
dynasties, with the last data point of each one being the requested
index. The index must be valid (use `get-high-scores` first to get the
maximum allowed index).

The server will send a binary frame in the same form as
`get-high-scores` (see above).

Then, the server will respond to the original message with no
additional data.


## Data files

The server sends data files as binary frames. The binary frames start
with a 32 bit little-endian file identifier, then the rest of the
frame is the raw data of that file.

File identifiers:

 * 1: `stars.dat`, the galaxy.
 * 2: `systems.dart`, the multiple star systems map.

The file identifier 0 is used by the high scores logic (see above).


## Galaxy (file 1)

The file with code 1 consists of little-endian 32 bit integers:

 * Integer 0: the number of star categories, N.
 * Integer 1..N: the number of stars in each category, M0, M1, M2, etc.
 * Integer N+1..N+M0*2: the stars in category 0.
 * Integer N+M0*2+1..N+M0*2+M1*2: the stars in category 1.
 * etc.

Each star is represented as two integers giving the X and Y
coordinates of the star, scaled so that the top left coordinate of the
galaxy is 0,0 and the bottom right coordinate of the galaxy is
4294967295,4294967295 (2^32-1).

Categories always have at least one star.

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

Category numbers are 0-255. Category numbers 11-255 are reserved for
future use.


## Canonical systems (file 2)

The file with code 2 consists of pairs of little-endian 32 bit
integers represent star IDs. The first of each pair is a star's ID,
and the second is the star ID of the primary star of that first star's
system. The whole file is sorted.

Stars are entries in the galaxy file (with code 1). Star IDs are
formed by shifting the category ID left by 20 bits, and adding the
offset into the category for the star.

Each category can have at most 1,048,575 (0x100000) stars (offsets 0x0
to 0xfffff).

Star IDs, by definition, do not have any of their top four bits set
(they are numbers in the range 0x00000000 to 0x0FFFFFFF).



# Internal Protocol

Raw TCP, starting with a null, a 4-byte length, a password of that
length, and then 4-byte length-prefixed frames.

Each frame starts with a 4-byte-length-prefixed string, the command.


## `add-score` (`icAddScoreDatum`)

Fields:

 * dynasty ID (4-byte integer)
 * score (double)

Response is one of:

 * 0x01 byte indicating success
 * disconnection indicating failure


## `await-scores` (`icAwaitScores`)

Only available in test mode.

Fields:

 * number of scores messages (4-byte integer)

Response is one of:

 * 0x01 byte indicating that the server has received that many score
   messages. The message will be delayed until it is true.
 * disconnection indicating failure
