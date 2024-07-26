# Systems Server Public Protocol

## `login`

Fields:

 * Access token from login server's `login` message.

Response:

 * A number giving the server version. This number is actually the
   highest known feature code that the server will use. If this number
   is higher than expected by the client, the client may fail to parse
   some server messages.

The server will subsequently begin sending updates about the systems
it supports that have the dynasty's presence, starting with a complete
system description for each system (of assets visible to this dynasty).

## System updates

Whenever the system changes, the system server sends a binary frame to
each affected client containing the updated information, in the form
of an <update> sequence:

```bnf
<update>            ::= <systemupdate>+

<systemupdate>      ::= <systemid> <assetid> <x> <y> <assetupdate>+ <systemterminator>

<systemid>          ::= 32 bit integer giving the system ID. For systems with
                        stars, this is the star ID of the canonical star.

<x>                 ::= position of system origin relative to galaxy left, in meters

<y>                 ::= position of system origin relative to galaxy top, in meters

<assetupdate>       ::= <assetid> <properties> <feature>* <assetterminator>

<assetid>           ::= non-zero 64 bit integer.

<systemterminator>  ::= zero as a 64 bit integer.

<properties>        ::= <classid> <dynasty> <double> <double> <string>

<dynasty>           ::= 32 bit integer (0 for unowned).

<feature>           ::= <featurecode> <featuredata>

<featurecode>       ::= non-zero 32 bit integer giving the feature code, see below.

<assetterminator>   ::= zero as a 32 bit integer.

<featuredata>       ::= feature-specific form, see below.

<classid>           ::= non-zero 32 bit integer.

<string>            ::= 32 bit integer followed by as many bytes as
                        specific by that integer.

<double>            ::= 64 bit float
```

The `<assetid>` in the `<systemupdate>` is the system's root asset
(usually a "space" asset that contains positioned orbits that
themselves have stars).

The `<properties>` are the asset class ID, the owner dynasty ID
(dynasty IDs, like all other IDs, are only meaningful per connection),
the asset's mass in kg, the asset's rough diameter in meters, and the
asset's name (if any; if not, the empty string).


### Features

Each feature has a code, which is one of the fcXXXX constants in
`../common/isdprotocol.pas`. For example, fcAssetName is 0x01.

The highest number reported by the server is the one reported in
response to the `login` message.

Each feature then has a specific form of data. The data is not
self-describing, so a client that does not support all current
features cannot decode server data.

#### `fcStar` (0x01)

```bnf
<featuredata>  ::= <starid>
<starid>       ::= 32 bit integer
```


#### `fcSpace` (0x02)

```bnf
<featuredata>  ::= <assetid> <childcount> <child>*
<childcount>   ::= 32 bit integer
<child>        ::= <double>{2} <assetid>
```

The first `<assetid>` is the asset at the origin.

There are many `<child>` repetitions as `<childcount>`. These children
have two `<double>` parameters which are the distance from the origin,
and the angle in radians clockwise from the positive x axis to that
child.


#### `fcOrbit` (0x03)

```bnf
<featuredata>  ::= <assetid> <orbitcount> <orbit>*
<orbitcount>   ::= 32 bit integer
<orbit>        ::= <double>{4} <assetid>
```

There are as many `<orbit>` repetitions as specified by
`<orbitcount>`. The first `<assetid>` is the child at the focal point.

The four `<double>` parameters for the `<orbit>` children are the
semi-major axis (in meters), eccentricity, theta (position around the
ordit in radians) at time zero, and omega (tilt of the orbit around
the focal point in radians clockwise from the positive x axis).


#### `fcStructure` (0x04)

```bnf
<featuredata>          ::= <materials quantity> <structural integrity>
<materials quantity>   ::= 32 bit integer
<structural integrity> ::= 32 bit integer
```

Mysterious feature that depends on asset class stuff that isn't documented yet.


# Systems Server Internal Protocol

Response in all cases is one of:

 * 0x01 byte indicating success
 * disconnection indicating failure

## `create-system` (`icCreateSystem`)

Fields:

 * 32 bit integer: system ID
 * 64 bit float: X position of center of system, in meters
 * 64 bit float: Y position of center of system, in meters
 * 32 bit integer: number of stars
 * for each star:
    * category (32 bit integer)
    * X distance from center of system (64 bit float)
    * Y distance from center of system (64 bit float)

The X and Y positions are relative to the top left corner of the galaxy.

The first star must be at the center of the system (so its two
distance values must be zero).


## `register-token` (`icRegisterToken`)

Fields:

 * dynasty ID (4-byte integer)
 * 4-byte-length-prefixed salt
 * 4-byte-length-prefixed password hash


## `logout` (`icLogout`)

Fields:

 * dynasty ID (4-byte integer)


## `trigger-scenario-new-dynasty` (`icTriggerNewDynastyScenario`)

Fields:

 * dynasty ID (4-byte integer)
 * dynasty server ID (4-byte integer)
 * system ID (4-byte integer)
