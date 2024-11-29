# Systems Server Public Protocol

## `login`

Fields:

 * Access token from login server's `login` message.

Response:

 * A number giving the server version. This number is actually the
   highest known feature code that the server will use. If this number
   is higher than expected by the client, the client might fail to
   parse some server messages.

The server will subsequently begin sending updates about the systems
it supports that have the dynasty's presence, starting with a complete
system description for each system (of assets visible to this dynasty).

## Change notifications

When the client connects, and whenever the system subsequently
changes, the system server sends a binary frame to each affected
client containing the updated information, in the form of an <update>
sequence:

```bnf
<update>            ::= (<notifications> | <systemupdate>)+
```

### Notifications

```bnf
<move>              ::= <notificationid> <payload>
<notificationid>    ::= 0x10000000 .. 0xFFFFFFFF
<payload>           ::= depends on the notification
```

This can be distinguished from a `<systemupdate>` because no
`<systemid>` above 0x0FFFFFFF exists, so notification IDs
(0x10000000-0xFFFFFFFF) don't overlap with the range of valid
`<systemid>` values.

There are currently no notifications defined.


### System updates

```bnf
<systemupdate>      ::= <systemid>
                        <currenttime> <timefactor> ; time data for system, see below
                        <assetid> <x> <y> ; center of system
                        <assetupdate>+ <zero64> ; assets

<systemid>          ::= <int32> ; the star ID of the canonical star, if any

<currenttime>       ::= <time> ; current time relative to system's t₀

<timefactor>        ::= <double> ; rate of time in system (usually 500.0)

<x>                 ::= position of system origin relative to galaxy left, in meters

<y>                 ::= position of system origin relative to galaxy top, in meters

<assetupdate>       ::= <assetid> <properties> <feature>* <zero32>

<assetid>           ::= non-zero 32 bit integer

<properties>        ::= <dynasty> ; owner
                        <double>  ; mass
                        <double>  ; size
                        <string>  ; name
                        <string>  ; icon
                        <string>  ; class name
                        <string>  ; description

<dynasty>           ::= <int32> ; zero for unowned

<feature>           ::= <featurecode> <featuredata>

<featurecode>       ::= <int32> ; non-zero, see below

<featuredata>       ::= feature-specific form, see below

<string>            ::= <int32> [ <int32> <byte>* ] ; see below

<time>              ::= 64 bit integer ; milliseconds

<bitflag>           ::= 8 bits

<double>            ::= 64 bit float

<int32>             ::= 32 bit unsigned integer

<int64>             ::= 64 bit unsigned integer

<zero32>            ::= 32 bit zero

<zero64>            ::= 64 bit zero
```

The `<systemid>` is currently always a star ID.

The `<currenttime>` gives the system's current actual time, in
milliseconds, relative to the system's origin time (t₀), which allows
positions in orbits to be computed.

The time in the system advances at the rate of `<timefactor>` seconds
per TAI second. The `<timefactor>` may be any finite number (including
zero and negative numbers), but will never be NaN or infinite.

The `<assetid>` in the `<systemupdate>` is the system's root asset
(usually an asset with the `fcSpace` feature, that contains positioned
orbits (assets with an `fcOrbit` feature) that themselves have stars
(assets with the `fcStar` feature) as their primary asset).

Asset IDs (`<assetid>`) are system-specific and dynasty-specific. They
remain stable so long as the asset is visible to the dynasty. If the
server ever sends an update that implies the asset is no longer
visible (e.g. its old parent is included in the update and does not
include it in its list of children, and no other asset includes it in
its list of children), then the ID is considered "released" and may be
reused for another asset.

Currently, asset IDs are guaranteed to be in the range 1..2^24. Asset
ID zero is reserved or indicating the absence of an asset.

The `<properties>` are the owner dynasty ID (zero for unowned assets),
the asset's mass in kg, the asset's rough diameter in meters, the
asset's name (if any; this is often the empty string), the icon name,
a class name (brief description of the object, e.g. "star", "planet",
"ship"), and a longer description of the object.

The diameter is always bigger than zero.

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

Each feature then has a specific form of data. The data format is not
self-describing (i.e. there is no way to know when a feature's data
ends and the next feature's begins), so a client that does not support
all current features cannot decode server data.

Features may appear multiple times per asset. For example, an asset
could have multiple `fcSpaceSensor` features with different settings.

#### `fcStar` (0x01)

```bnf
<featuredata>       ::= <starid>
<starid>            ::= <int32>
```


#### `fcPlanetaryBody` (0x07)

```bnf
<featuredata>       ::= <hp>
<hp>                ::= <int32>
```

The planetary body feature describes a non-stellar celestial feature
such as a planet, moon, dwarf planet, asteroid, etc.

The `<hp>` number indicates the structural integrity of the body. It
is reduced when the planet is mined, bombarded, or otherwise
compromised. At zero, the planet will disintegrate, probably forming a
new planetary body with no structures on it.


#### `fcSpace` (0x02)

```bnf
<featuredata>       ::= <assetid> <childcount> <child>*
<childcount>        ::= <int32>
<child>             ::= <double>{2} <assetid>
```

The first `<assetid>` is the asset at the origin.

There are many `<child>` repetitions as `<childcount>`. These children
have two `<double>` parameters which are the distance from the origin,
and the angle in radians clockwise from the positive x axis to that
child (the angle may be negative).

It is extremely likely, though not guaranteed, that the listed assets
will have an `fcOrbit` feature.

> TODO: the first child might not be at the origin either.


#### `fcOrbit` (0x03)

```bnf
<featuredata>       ::= <assetid> <orbitcount> <orbit>*
<orbitcount>        ::= <int32>
<orbit>             ::= <double>{3} <time> <direction> <assetid>
<direction>         ::= <bitflag> ; 0x01 or 0x00
```

There are as many `<orbit>` repetitions as specified by
`<orbitcount>`. The first `<assetid>` is the child at the focal point.
That asset will not have an `fcOrbit` feature. (It is extremely
likely, though not guaranteed, that the other listed assets _will_
have such a feature.)

The three `<double>` parameters for the `<orbit>` children are the
semi-major axis (in meters), the eccentricity, and _omega_ (tilt of
the orbit around the focal point in radians clockwise from the
positive x axis). The `<time>` is the orbit time origin, which is the
number of milliseconds after the system's zero time at which to
consider the orbit's zero time (t₀), at which point the child is at
periapsis. The `<direction>` is 0x01 if the orbit is clockwise, and
0x00 if it's counter-clockwise. The other 31 bits are reserved for
future flags.

The current position is computed from the current system time and the
time factor, as follows:

   Let _t_ be the current system time minus the orbit time origin.
   Let _a_ be the orbit's semi-major axis.
   Let _e_ be the orbit's eccentricity (0<=e<=0.95).
   Let _G_ be the gravitational constant, defined for ISD as 6.67430e-11.
   Let _M_ be the mass of the child at the focal point.
   Let _T_ be the orbital period,
     computed as `2*pi*sqrt((a^3)/(G*M))`.
   Let _tau_ be the fraction of the period,
     computed as `(t % T) / T`.
   Let _q_ be the approximation constant,
     computed as `-0.99*pi/4*(e-3*sqrt(e))`.
   Let _theta_ be the estimate of the angle from the focal point on the
     semi major axis to the orbital child, which when e=0.0 is
     computed as `2*pi*tau`, and when e>0.0 is
     computed as `2*pi*(tan(tau*2*q - q) - (tan(-q))) / (tan(q)-tan(-q))`,
     then negated if _direction_ is counter-clockwise.
   Let _L_ be the semi lactus rectum length,
     computed as `a * (1 - e*e)`.
   Let _r_ be the distance between the orbiting child and the child
     at the focal point,
     computed as `L / (1 + e * cos(theta))`.

The position of the child relative to the focal point is thus:

    x = r * cos(theta + omega)
    y = r * sin(theta + omega)

The orbit can be further described by an ellipse whose components are
computed as follows:

   Let _b_ be computed as `a * sqrt(1 - e*e)`.
   Let _c_ be computed as `e * a`.
   Let _w_ be computed as `a * 2`.
   Let _h_ be computed as `b * 2`.

The orbit itself is the ellipse that fills the rectangle whose center
is _c_ to the left of the focal point, with width _w_ and _h_, rotated
about the center by _omega_.

The `q` and `theta` values in particular are vague approximations for
gameplay purposes and are not empirically accurate.

It is guaranteed that for an orbit that is itself the child of an
asset's orbit feature, if that parent orbit's focal point child's mass
is M*, and the parent orbit's semi-major axis is a' and the parent
orbit's eccentricity is e', then:

    ((1 + e) * a) / ((1 - e') * a') < cuberoot(M / (3 * (M + M*)))

When a body's orbit is such that the distance between the primary body
(at `c=e*a`) and the secondary body at `theta=0` (at `a`) is less than
the sum of the bodies' radii, the bodies will collide when the time
comes such that `theta=0`.

Eccentricities greater than 0.95 are not modeled by this
approximation, and in practice will use different features (e.g. an
`fcSpace` feature).


#### `fcStructure` (0x04)

```bnf
<featuredata>       ::= <material-lineitem>* <zero32> <hp> <minhp>
<material-lineitem> ::= <marker> <quantity> <max> <componentname> <materialname> <materialid>
<marker>            ::= 0xFFFFFFFF as an unsigned 32 bit integer
<quantity>          ::= <int32>
<max>               ::= <int32>
<componentname>     ::= <string>
<materialname>      ::= <string>
<materialid>        ::= <int32> ; non-zero material id, or zero if it's not recognized
<hp>                ::= <int32>
<minhp>             ::= <int32>
```

The structure feature describes the make-up and structural integrity
of the asset.

Each material line item (`<material-lineitem>`) consists of the
following data:

 * a marker to distinguish it from the terminating zero.
 * how much of the material is present.
 * how much of the material is required (0 if the asset class is not known).
 * the name of the component (an empty string if the asset class is not known).
 * a brief description of the material (may not be unique).
 * the ID of the material, or zero if the material is not recognized.

Material IDs (`<materialid>`) are globally unique (stable across
systems and servers), but are only provided for recognized materials
(so the same material might sometimes be reported as zero and
sometimes with an ID).

Material line items that have zero material present are skipped when
the asset class is not known.

The description of the material in this list (`<materialname>`) can be
ignored if the material is known, as the material data (found in a
knowledge base) will have a more detailed description.

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

TODO: Currently the structural integrity values have no effect.


### `fcSpaceSensor` (0x05)

```bnf
<featuredata>       ::= <reach> <up> <down> <resolution> [<feature>]
<reach>             ::= <int32> ; max steps up tree to nearest orbit
<up>                ::= <int32> ; distance that the sensors reach up the tree from the nearest orbit
<down>              ::= <int32> ; distance down the tree that the sensors reach
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
<count>             ::= <int32> ; number of detected assets
```

Reports the "top" and "bottom" nodes of the tree that were affected by
the sensor sweep of the immedietaly preceding `fcSpaceSensor` feature
(see `fcSpaceSensor`), as well as the total number of detected nodes.

This feature, if present, always follows a `fcSpaceSensor` feature. If
there are multiple sensors, they may each have a trailing
`fcSpaceSensorStatus`; each status applies to the immediately
preceding sensor.


### `fcPlotControl` (0x08)

```bnf
<featuredata>       ::= <int32>
```

Indicates to the client that the asset has, or could have, some
important plot relevance. The server will send a single integer as the
feature's data, which will be one of the following:

 0: Nothing. (Normally the feature would just be omitted in this case.)
 
 1: This is the colony ship, or possibly the remnants of the colony
    ship, that started the dynasty's story. Only one asset in the
    entire galaxy will ever have this flag set for a particular
    dynasty (even if they somehow obtain another colony ship, e.g. by
    taking over another dynasty; the other dynasty's ship will not
    have this set). When a client sees an asset with this code for the
    first time during a session, it is reasonable to center on the
    associated asset.


### `fcSurface` (0x09)

```bnf
<featuredata>       ::= <regioncount> <region>*
<regioncount>       ::= <int32> ; always 1
<region>            ::= <assetid>
```

Describes the geographical regions of a planetary body. Currently,
only one region is supported per planetary body, and no geological
features are described, but it is expected that this will change in
due course.

The assets in regions of a planetary surface are expected to have the
`fcGrid` feature, but this is not guaranteed.

> TODO: provide geology and more than one region.


### `fcGrid` (0x0A)

```bnf
<featuredata>       ::= <cellsize> <width> <height> <count> <cell>*
<cellsize>          ::= <double> ; meters
<width>             ::= <int32> ; greater than zero
<height>            ::= <int32> ; greater than zero
<count>             ::= <int32>
<cell>              ::= <x> <y> <assetid>
<x>                 ::= <int32> ; 0..width-1
<y>                 ::= <int32> ; 0..height-1
```

Grids consist of square cells.

The `<cellsize>` represents the width and height of each cell of the
grid, in meters.

There are `<width>` cells horizontally and `<height>` cells vertically.

Precisely `<count>` instances of `<cell>` follow the dimensions. These
specify the contents of the grid, in no particular order. Each cell is
at the specified `<x>`/`<y>` coordinate in the grid.

> TODO: provide geology within each cell.

> TODO: support rectangular grids. Current width and height are always equal.


### `fcPopulation` (0x0B)

```bnf
<featuredata>       ::= <int64> <double>
```

The integer is the number of people at this population center.
The double is their mean happiness.


### `fcMessageBoard` (0x0C)

```bnf
<featuredata>       ::= <messagecount> <message>*
<messagecount>      ::= <int32>
<message>           ::= <assetid>
```

The number of children, followed by all their IDs.

Children are expected to have `fcMessage` features, though this is not
guaranteed.


### `fcMessage` (0x0D)

```bnf
<featuredata>       ::= <source> <timestamp> <flags> <subject> <from> <body>
<source>            ::= <systemid>
<timestamp>         ::= <time> ; system time
<flags>             ::= <bitflag> ; 0x01 means "read"
<subject>           ::= <string>
<from>              ::= <string>
<body>              ::= <string>
```

The `<source>` specifies the system ID where the message was spawned.

The `<timestamp>` is in the time frame of the source system and is
meaningless outside that context.

The `<flags>` bit field has eight bits interpreted as follows:

   0 (LSB): When set, the message has already been read.
   1      : reserved, always zero
   2      : reserved, always zero
   3      : reserved, always zero
   4      : reserved, always zero
   5      : reserved, always zero
   6      : reserved, always zero
   7 (MSB): reserved, always zero

The `<subject>` is a string that is guaranteed to not contain a line
feed, that is a heading for the message.

The `<from>` is a string that somehow identifies (to the player) the
source of the message. This might be a character in the story, or a
specific asset, or something else. For example, "Dr Blank" or
"Stockpile #3 in Geneva on Earth in the Sol system". Clients are
advised against attempting to map this string to actual assets in the
game world, as the strings are not unambiguous.

Finally the message contains a `<body>`, which is a string representing
the message. Currently this is plain text.

> TODO: A future version of this protocol will change `<body>` to
> support formatting, images, links to assets, etc.


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
