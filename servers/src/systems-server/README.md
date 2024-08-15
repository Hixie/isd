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

<systemupdate>      ::= <systemid>
                        <currenttime> <timefactor> ; time data for system, see below
                        <assetid> <x> <y> ; center of system
                        <assetupdate>+ <zero> <zero> ; assets

<systemid>          ::= <integer> ; the star ID of the canonical star, if any

<currenttime>       ::= 64 bit integer ; current time relative to system's t₀

<timefactor>        ::= <double> ; rate of time in system (usually 500.0)

<x>                 ::= position of system origin relative to galaxy left, in meters

<y>                 ::= position of system origin relative to galaxy top, in meters

<assetupdate>       ::= <assetid> <properties> <feature>* <zero>

<assetid>           ::= non-zero 64 bit integer

<properties>        ::= <dynasty> ; owner
                        <double>  ; mass
                        <double>  ; size
                        <string>  ; name
                        <string>  ; icon
                        <string>  ; class name
                        <string>  ; description

<dynasty>           ::= <integer> ; zero for unowned

<feature>           ::= <featurecode> <featuredata>

<featurecode>       ::= <integer> ; non-zero, see below

<featuredata>       ::= feature-specific form, see below

<string>            ::= <integer> [ <integer> <byte>* ] ; see below

<double>            ::= 64 bit float

<integer>           ::= 32 bit unsigned integer

<zero>              ::= 32 bit zero
```

The `<systemid>` is currently always a star ID.

The `<currenttime>` gives the system's current actual time, in
milliseconds, relative to the system's origin time (t₀), which allows
positions in orbits to be computed.

The time in the system advances at the rate of `<timefactor>` seconds
per TAI second. The `<timefactor>` may be any finite number (including
zero and negative numbers), but will never be NaN or infinite.

The `<assetid>` in the `<systemupdate>` is the system's root asset
(usually a "space" asset that contains positioned orbits that
themselves have stars).

Asset IDs (`<assetid>`) are connection-specific.

The `<properties>` are the owner dynasty ID (zero for unowned assets),
the asset's mass in kg, the asset's rough diameter in meters, the
asset's name (if any; this is often the empty string), the icon name,
a class name (brief description of the object, e.g. "star", "planet",
"ship"), and a longer description of the object.

The class name may vary in precision based on the knowledge that the
dynasty's observing asset has. The icon generally does not vary.

The longer description may be vague or otherwise change based on the
specifics of the situation; for example, it is typically "Unknown
object type." when the dynasty does not have knowledge of the object
type, or "Not currently visible or otherwise detectable." when the
player cannot see the object (but can infer its presence).

Strings (`<string>`) in this format are deduplicated as follows. The
first time a particular string is encountered, it is serialized as a
32 bit integer identifier, then the string's length, then that many
bytes giving the string data. The second time, only the identifier is
specified. String identifiers are scoped to the connection.


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
<featuredata>       ::= <starid>
<starid>            ::= <integer>
```


#### `fcSpace` (0x02)

```bnf
<featuredata>       ::= <assetid> <childcount> <child>*
<childcount>        ::= <integer>
<child>             ::= <double>{2} <assetid>
```

The first `<assetid>` is the asset at the origin.

There are many `<child>` repetitions as `<childcount>`. These children
have two `<double>` parameters which are the distance from the origin,
and the angle in radians clockwise from the positive x axis to that
child (the angle may be negative).


#### `fcOrbit` (0x03)

```bnf
<featuredata>       ::= <assetid> <orbitcount> <orbit>*
<orbitcount>        ::= <integer>
<orbit>             ::= <double>{4} <assetid>
```

There are as many `<orbit>` repetitions as specified by
`<orbitcount>`. The first `<assetid>` is the child at the focal point.

The four `<double>` parameters for the `<orbit>` children are the
semi-major axis (in meters), eccentricity, theta (position around the
ordit in radians) at time zero (t₀), and omega (tilt of the orbit
around the focal point in radians clockwise from the positive x axis).

The current position is computed from the current system time and the
time factor.


#### `fcStructure` (0x04)

```bnf
<featuredata>       ::= <material-lineitem>* <zero> <hp> <minhp>
<material-lineitem> ::= <marker> <quantity> <max> <componentname> <materialname> <materialid>
<marker>            ::= 0xFFFFFFFF as an unsigned 32 bit integer
<quantity>          ::= <integer>
<max>               ::= <integer>
<componentname>     ::= <string>
<materialname>      ::= <string>
<materialid>        ::= <integer> ; non-zero material id
<hp>                ::= <integer>
<minhp>             ::= <integer>
```

The structure feature describes the make-up and structural integrity
of the asset.

Each material line item (`<material-lineitem>`) consists of the
following data:

 * a marker to distinguish it from the terminating zero.
 * how much of the material is present.
 * how much of the material is required (0 if the asset class is not known).
 * the name of the component (an empty string if the asset class is not known).
 * a brief description of the material.
 * the ID of the material.

Material IDs (`<materialid>`) are connection-specific.

Material line items that have zero material present are skipped when
the asset class is not known.

The description of the material in this list can be ignored if the
material is known, as the material data will have a more detailed
description.

The list of material line items is terminated by a zero (instead of
the 0xFFFFFFFF marker).

After the material line items, the following values describing the
asset's structural integrity are given:

 * a number indicating the structural integrity of the asset.
 * the minimum required structural integrity for the object to
   function (0 if the asset class is not known).

The maximum structural integrity is the sum of the quantities in the
material line items (which may be incomplete if the asset class is not
known). The current structural integrity can't be greater than the sum
of the quantities of material preset.

TODO: Currently the material IDs are opaque.
      Currently the structural integrity values have no effect.


### `fcSpaceSensor` (0x05)

```bnf
<featuredata>       ::= <reach> <up> <down> <resolution> [<feature>]
<reach>             ::= <integer> ; max steps up tree to nearest orbit
<up>                ::= <integer> ; distance that the sensors reach up the tree from the nearest orbit
<down>              ::= <integer> ; distance down the tree that the sensors reach
<resolution>        ::= <double> ; the minimum size of assets that these sensors can detect (meters)
```

Space sensors work by walking up the tree from the sensor up to the
nearest orbit (going a max of `<reach>` steps), then going a further
<up> steps up the tree, then going down from that in a depth-first
search of orbits, up to `<down>` levels. Sensors can detect any asset
that is at least `<resolution>` meters in size and is in an orbit
examined during this walk.

The trailing `<feature>`, if present, is a `fcSpaceSensorStatus`
feature, documented next.


### `fcSpaceSensorStatus` (0x06)

```bnf
<featuredata>       ::= <nearest-orbit>
                        <top-orbit>
                        <count>
<nearest-orbit>     ::= <assetid>
<top-orbit>         ::= <assetid>
<count>             ::= <integer> ; number of detected assets
```

Reports the "top" and "bottom" nodes of the tree that were affected by
the sensor sweep (see `fcSpaceSensor`), as well as the total number
of detected nodes.

This feature, if present, always follows a `fcSpaceSensor` feature.


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
