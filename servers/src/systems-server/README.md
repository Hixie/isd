# Systems Server Public Protocol

See the README.md in the parent directory for context.

## `login`

Fields:

 * Access token from login server's `login` message.

Response:

 * A number (uint64) giving the server version. This number is
   actually the highest known feature code that the server will use.
   If this number is higher than expected by the client, the client
   might fail to parse some server messages.

The server will subsequently begin sending updates about the systems
it supports that have the dynasty's presence, starting with a complete
system description for each system (of assets visible to this dynasty).


## `play`

Fields:

 * System ID (uint64)
 * Asset ID (uint64)
 * Command (string)
 * additional fields defined by the command

The connection must have had a successful `login` prior to this message.

The command is routed to the given asset, which must either be unowned
or owned by the dynasty, must be visible, and whose asset class must
be known. For details about which commands are available for assets
with various features, see the feature definitions below. Unless
otherwise stated, features do not support any commands.


## Change notifications

When the client connects, and whenever the system subsequently
changes, the system server sends a binary frame to each affected
client containing the updated information, in the form of a
<systemupdate> sequence.

Binary frames that start with a `uint32` in the range 0x10000000 ..
0xFFFFFFFF are reserved for use in future extensions to the protocol
but are currently never sent by the server.


### System updates

```bnf
<systemupdate>      ::= <systemid>
                        <currenttime> <timefactor> ; time data for system, see below
                        <assetid> <x> <y> ; center of system
                        <assetupdate>+ <zero64> ; assets

<systemid>          ::= <uint32> ; the star ID of the canonical star, if any
                        ; always in the range 0x00200000 to 0x0FFFFFFF
                        ; star IDs are in the range 0x00200000 to 0x00AFFFFF
                        ; starless systems are in the range 0x00B00000 to 0x0FFFFFFF

<currenttime>       ::= <time> ; current time relative to system's t₀

<timefactor>        ::= <double> ; rate of time in system (usually 500.0)

<x>                 ::= <double> ; position of system origin relative to galaxy left, in meters

<y>                 ::= <double> ; position of system origin relative to galaxy top, in meters

<assetupdate>       ::= <assetid> <properties> <feature>* <zero32>

<assetid>           ::= <uint32> ; non-zero

<assetclassid>      ::= <int32> ; zero indicates absence

<assetclass>        ::= <assetclassid> ; id, may be zero when used in <properties>
                        [ ; see below for details on when this section is included
                          <string>  ; icon
                          <string>  ; class name
                          <string>  ; description
                        ]

<properties>        ::= <dynasty> ; owner
                        <double>  ; mass
                        <double>  ; mass flow rate
                        <double>  ; size (diameter)
                        <string>  ; name
                        <assetclass> ; may have id zero

<materialid>        ::= <int32> ; non-zero material id

<dynasty>           ::= <uint32> ; zero for unowned

<feature>           ::= <featurecode> <featuredata>

<featurecode>       ::= <uint32> ; non-zero, see below

<featuredata>       ::= feature-specific form, see below

<string>            ::= <uint32> [ <uint32> <byte>* ] ; see below

<time>              ::= 64 bit signed integer ; milliseconds

<byte>              ::= 8 bits

<double>            ::= 64 bit float

<int32>             ::= 32 bit signed integer

<uint32>            ::= 32 bit unsigned integer

<int64>             ::= 64 bit signed integer

<uint64>            ::= 64 bit unsigned integer

<zero8>             ::= 8 bit zero

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

The root asset must have one of the following features:

 * `fcSpace`.

Asset IDs (`<assetid>`) are system-specific and dynasty-specific. They
remain stable so long as the asset is visible to the dynasty. If the
server ever sends an update that implies the asset is no longer
visible (e.g. its old parent is included in the update and does not
include it in its list of children, and no other asset includes it in
its list of children), then the ID is considered "released" and may be
reused for another asset. When this happens, other assets that
referenced this ID should be assumed to have changed to sending the
asset ID zero instead of the previous ID, even if they do not send an
update.

An asset ID is guaranteed to not be reused until an update has been
sent that indicates its absence.

Asset IDs may be mentioned before their first `<assetupdate>`, though
if an asset ID is referenced before its first `<assetupdate>`, that
`<assetupdate>` is guaranteed to be included in the same overall
`<systemupdate>`.

Asset ID zero is reserved for indicating the absence of an asset
(either because no such asset exists, or because the player cannot see
the asset in question).

The `<properties>` are the owner dynasty ID (zero for unowned assets),
the asset's mass in kg and mass flow rate in kg/ms, the asset's size
(rough diameter in meters), the asset's name (if any; this is often
the empty string), the asset's class ID, the class' icon name, a class
name (brief description of the object, e.g. "star", "planet", "ship"),
and a longer description of the object. The icon, class name, and
description are the same as the asset class icon, name, and
description, if the asset class is known.

The mass flow rate is the rate of change of mass of the object. For
example, as a pile of dirt grows, its mass will grow. Rather than
repeatedly sending data from the server to the client, the server will
report a non-zero mass flow rate.

Some assets are considered _physical_, and some are considered
_virtual_. Physical assets have a non-zero size, virtual assets will
have a zero size, as well as zero mass and zero mass flow rate.
Physical assets represent objects in the game world, while virtual
assets represent data, e.g. messages in a message board.

The root asset will always be a physical asset. All descendants of
virtual assets will be virtual. Unless otherwise specified, the
children of physical assets are physical. It is an error if the server
sends a virtual asset where a physical asset is expected, or vice
versa.

Asset class IDs are numbers in the range -2,147,483,648 to
2,147,483,647, but not zero (i.e. signed 32 bit integers).

The class name may vary in precision based on the knowledge that the
dynasty's observing asset has. The icon generally does not vary.

The longer description may be vague or otherwise change based on the
specifics of the situation; for example, it is typically "Unknown
object type." when the dynasty does not have knowledge of the object
type, or "Not currently visible or otherwise detectable." when the
player cannot see the object (but can infer its presence).

#### Deduplication for strings and asset classes

To avoid duplication, strings (`<string>`) are identified by a
connection-specific unique identifier.

The empty string is always represented by the identifier zero.

Other strings are identified by 32 bit integers above zero. The first
time a particular identifier other than zero is sent, it is followed
by a 32 bit integer giving its (non-zero) length, then that many bytes
giving the string data in UTF-8.

Subsequently, only the identifier is given. String identifiers are
scoped to the connection.

Asset classes (<`assetclass`>) are handled similarly. When the asset
class ID is zero (this is only possible as part of a `<properties>`
list; other uses of `<assetclass>` never allow a zero ID), all the
fields are included. When the asset class ID is not zero, the fields
are included the first time the asset class ID is mentioned on a
connection; the second and subsequent occurrences only give the asset
class ID. (Asset class details never change during a connection.)

> TODO: deduplicate materials in a similar way.


### Icons

An image file can be obtained for a given `icon` value by fetching a
file whose name is the icon with a `.png` extension, from
<https://interstellar-dynasties.space/icons/>. For example, if the
icon is "space ship", then the image is available at
<https://interstellar-dynasties.space/icons/space%20ship.png>.

The images have an `ISD-Fields` header whose value matches the
following grammar:

```bnf
<isdfields>         ::= <size> (WS? ";" WS? <fields>)*
<size>              ::= <width> WS <height>
<fields>            ::= <x> WS <y> WS <width> WS <height> WS <uiwidth>
<x>                 ::= <integer>
<y>                 ::= <integer>
<width>             ::= <integer>
<height>            ::= <integer>
<uiwidth>           ::= <integer>
<integer>           ::= <one or more "0" to "9">
WS                  ::= <one or more spaces or tabs>
```

The `<size>` gives a nominal width and height by which the `<fields>`
are to be interpreted.

The `<fields>` give the x, y, width, and height of rectangles in the
image, relative to the image being the given size. The `<uiwidth>`
specifies the number of logical pixels that the UI should assign to
the width of the field.

For example, if an image that is actually 1000x1000 physical pixels
has an ISD-Fields field that says:

```http
ISD-Fields: 100 100; 0 0 10 10 100; 20 90 60 10 100
```

...then the image has a square field at its top left that is 10% of
the width and height of the image, into which UI should be placed so
that it is scaled to have 100 logical pixels of width (and height);
and a rectangular field centered at the bottom of the image whose
width is 60% of the image, whose height is 10% of the image, and into
which UI with a width of 100 logical pixels (and a height of about 16
logical pixels) can be placed.

Each feature can have one UI element. UI elements should be placed
into fields in the same order as the features are sent by the server.


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
<starid>            ::= <uint32>
```


#### `fcSpace` (0x02)

```bnf
<featuredata>       ::= <assetid> <child>* <zero32>
<child>             ::= <assetid> <double>{2}
```

The first `<assetid>` is the asset at the origin.

The children have two `<double>` parameters which are the distance
from the origin, and the angle in radians clockwise from the positive
x axis to that child (the angle may be negative).

It is extremely likely, though not guaranteed, that the listed assets
will have an `fcOrbit` feature.

> TODO: the first child might not be at the origin either.


#### `fcOrbit` (0x03)

```bnf
<featuredata>       ::= <assetid> <orbit>* <zero32>
<orbit>             ::= <assetid> <double>{3} <time> <direction>
<direction>         ::= <byte> ; 0x01 or 0x00
```

The first `<assetid>` is the child at the focal point. That asset will
not have an `fcOrbit` feature. It is extremely likely, though not
guaranteed, that the other listed assets _will_ have such a feature.

The children of an `fcOrbit` feature should always have a mass flow
rate of zero. Deviations from this by definition indicate a server bug
at this time.

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
<featuredata>       ::= <material-lineitem>* <zero32> <builder> <quantity> <rate> <hp> <rate> <minhp>
<material-lineitem> ::= <max> <componentname> <materialname> [<materialid> | <zero32>]
<max>               ::= <uint32>
<componentname>     ::= <string>
<materialname>      ::= <string>
<builder>           ::= <assetid> | <zero32>
<quantity>          ::= <uint64>
<hp>                ::= <uint64>
<rate>              ::= <double> ; units per millisecond
<minhp>             ::= <uint64>
```

The structure feature describes the make-up and structural integrity
of the asset.

Each material line item (`<material-lineitem>`) consists of the
following data:

 * how much of the material is required (may be smaller than real if
   the asset class is not known, but will never be zero).
 * the name of the component (an empty string if the asset class is
   not known).
 * a brief description of the material (may not be unique).
 * the ID of the material, or zero if the material is not recognized.

Material IDs (`<materialid>`) are globally unique (stable across
systems and servers), but are only provided for recognized materials
(so the same material might sometimes be reported as zero and
sometimes with an ID).

When the _asset class_ is not known, material line items will have
their `<max>` set their current quantity (so the `<max>` may change
over time).

The description of the material in this list (`<materialname>`) can be
ignored if the material is known, as the material data (found in an
`fcKnowledge` feature) will have a more detailed description.

The list of material line items is terminated by a zero.

After the material line items, if the structure is actively being
built, then the asset ID of the builder doing the building will be
specified as `<builder>`. Otherwise, this will be a zero.

Following this, values describing the asset's structural integrity are
given:

 * `<quantity>`: a number indicating how much material is in the
   asset. This is between zero and the sum of the `<max>` values, and
   fills components in the order given.
   
 * `<rate>` (1): the rate at which that number is increasing.
 
 * `<hp>`: a number indicating the structural integrity of the asset.
 
 * `<rate>` (2): the rate at which _that_ number is increasing.
 
 * `<minhp>`: the minimum required structural integrity for the object
   to function (if the asset class is not known, this will be zero; it
   can also be zero even if the asset class _is_ known, meaning the
   asset does not require its structure to be functional, e.g. for an
   asset that is also an `fcOrePile`).

The maximum structural integrity is the sum of the quantities in the
material line items (which may be incomplete if the asset class is not
known). The current structural integrity can't be greater than the
amount of material present, regardless of the indicated rate of
increase.

Structures support the following command:

 * `dismantle`: No fields. Can only be sent to unowned assets or
   assets owned by the player. If there are destructors nearly (e.g. a
   population center), removes the asset, transferring any resources
   to other assets as necessary. If anything cannot be removed, the
   asset will instead be replaced by a rubble pile with those
   materials. If there's no nearby destructors, responsds with a "`no
   destructors`" error.


#### `fcSpaceSensor` (0x05)

```bnf
<featuredata>       ::= <disabled> <reach> <up> <down> <resolution> [<feature>]
<reach>             ::= <uint32> ; max steps up tree to nearest orbit
<up>                ::= <uint32> ; distance that the sensors reach up the tree from the nearest orbit
<down>              ::= <uint32> ; distance down the tree that the sensors reach
<resolution>        ::= <double> ; the minimum size of assets that these sensors can detect (meters)
```

For the `<disabled>` field, see below.

Space sensors work by walking up the tree from the sensor up to the
nearest orbit (going a max of `<reach>` steps), then going a further
<up> steps up the tree, then going down from that in a depth-first
search of orbits, up to `<down>` levels. Sensors can detect any asset
that is at least `<resolution>` meters in size and is in an orbit
examined during this walk.

The trailing `<feature>`, if present, is a `fcSpaceSensorStatus`
feature, documented next. It is omitted if the sensor is disabled.


#### `fcSpaceSensorStatus` (0x06)

```bnf
<featuredata>       ::= <nearest-orbit>
                        <top-orbit>
                        <count>
<nearest-orbit>     ::= <assetid> | <zero32>
<top-orbit>         ::= <assetid> | <zero32>
<count>             ::= <uint32> ; number of detected assets
```

The status of an `fcSpaceSensor`.

Reports the nodes that are the nearest orbit to the sensor (bottom),
and the furthest orbit that could be reached by the sensor (top)
during its sweep, as well as the total number of detected nodes. By
definition, these nodes are visible to the user, because they are
ancestors of the asset with the `fcSpaceSensor`, and ancestors of
assets are always at least inferred.

If the sensor could not detect anything, e.g. because its `<reach>` is
too low given its position, then the "top" and "bottom" nodes will be
zero.

This feature, if present, always follows a `fcSpaceSensor` feature. If
there are multiple sensors, they may each have a trailing
`fcSpaceSensorStatus`; each status applies to the immediately
preceding sensor.


#### `fcPlanetaryBody` (0x07)

```bnf
<featuredata>       ::= <seed>
<seed>              ::= <uint32>
```

The planetary body feature describes a non-stellar celestial feature
such as a planet, moon, dwarf planet, asteroid, etc.

The seed determines the planet's geological features.

> TODO: define how


#### `fcPlotControl` (0x08)

```bnf
<featuredata>       ::= <uint32>
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


#### `fcSurface` (0x09)

```bnf
<featuredata>       ::= <region>* <zero32>
<region>            ::= <assetid> <x> <y>
<x>                 ::= <double> ; m from center to center
<y>                 ::= <double> ; m from center to center
```

Describes the geographical regions of a planetary body.

The assets in regions of a planetary surface are expected to have the
`fcRegion` and `fcGrid` features, but this is not guaranteed.


#### `fcGrid` (0x0A)

```bnf
<featuredata>       ::= <cellsize> <dimension> <cell>* <zero32> <buildables>
<cellsize>          ::= <double> ; meters
<dimension>         ::= <uint32> ; greater than zero
<cell>              ::= <assetid> <x> <y> <size>
<x>                 ::= <uint32> ; 0..width-1
<y>                 ::= <uint32> ; 0..height-1
<buildables>        ::= [ <assetclass> <size> ]* <zero32> ; asset classes do not have id zero
<size>              ::= <byte>
```

Grids consist of square cells.

The `<cellsize>` represents the width and height of each cell of the
grid, in meters.

There are `<dimension>` cells horizontally and `<dimension>` cells
vertically (grids are always square).

The children (the grid contents) are provided in no particular order.
Each cell is at the specified `<x>`/`<y>` coordinate in the grid, and
has a `<size>`. The given coordinate is the cell at the top left of
the asset, and the asset takes a square of `<size>` cells to a side,
growing down and to the right. (Thus, an asset of `<size>` 1 uses just
the cell at `<x>`,`<y>`.)

> TODO: provide geology within each cell.

The `<buildables>` lists the asset classes that can be built on this
grid. Each is followed by a size, which is the number of cells in each
dimension that the asset would take if built. (This is a number in the
range 1..255 or 1..`<dimension>`, whichever is smaller.) It is an
error if this list is not empty in the case of the asset class not
being known or the grid itself not being detectable.

This feature supports the following command:

 * `build`: two numeric fields, x and y, indicating a cell, followed
   by the asset class ID (from the `<buildables>`). There must be
   sufficient room to fit the asset with its top-left at the
   designated cell. Assets take as much room as specified in the
   `<buildables>` list. No data is returned.


#### `fcPopulation` (0x0B)

```bnf
<featuredata>       ::= <disabled> <count> <max> <jobs> <gossip>* <zero32>
<count>             ::= <uint32>
<max>               ::= <uint32>
<jobs>              ::= <uint32>
<gossip>            ::= <message> <source> <impactanchor> <impact> <duration> <peopleanchor> <people> <spreadrate>
<message>           ::= <string> ; description of event (cannot be empty)
<source>            ::= <assetid> | <zero32> ; asset that generated the gossip
<impactanchor>      ::= <time> ; time that <impact> was last updated
<impact>            ::= <double> ; per-person happiness delta
<duration>          ::= <uint64> ; number of in-system milliseconds that impact will last, relative to <impactanchor>
<peopleanchor>      ::= <time> ; time that <people> was last updated
<people>            ::= <uint32> ; number of people affected
<spreadrate>        ::= <double> ; spread factor per millisecond
```

For the `<disabled>` field, see below.

The `<count>` is the number of people at this population center. The
`<max>` is the maximum number of people that can be comfortably housed
at this population center (On occasion, `<count>` may exceed it,
especially if it is zero; this indicates overpopulation and is likely
to have a negative impact on happiness.) The `<jobs>` is the number of
people who are working at some `fcStaffing` feature.

Gossip is how the game represents happiness. Each gossip item
represents some impact on happiness. The message is a generic
description of the situation (and does not end with punctuation).

The happiness contribution of each gossip is computed as follows:
 
    age = now - impactanchor
    actual impact = impact * decay(age / duration)
    spreadtime = now - peopleanchor
    actual people = min(people * pow(spreadrate, spreadtime), count)
    happiness contribution = actual impact * actual people

...where `pow` is a function that raises the first argument to the
power of the second argument, `min` is a function that returns the
lower of its two arguments, and `decay` is a function that computes
its result as follows:

    decay(x) = 1 - x * x * (3 - 2 * x)  ; 0 <= x <= 1

Gossips whose `age` exceeds their `<duration>` have expired and should
no longer be considered present (and would not be sent by the server
in the server's next update).

The total happiness contribution of an `fcPopulation` feature is the
sum of the happiness contributions of all its `<gossip>`s.

The `<source>` is an asset, but will be zero if the asset is not
visible in the current system (e.g. if it was destroyed, or the assets
moved so as to be in different systems). When a gossip item's source
is set to zero, it may be merged with other similar gossip items.

The `<impactanchor>` and `<peopleanchor>` values may be different and
may not necessarily be when the gossip item was created.


#### `fcMessageBoard` (0x0C)

```bnf
<featuredata>       ::= <messages>* <zero32>
<messages>          ::= <assetid>
```

Child assets of a `fcMessageBoard` (the `<messages>`) must be virtual
and must have an `fcMessage` feature. They may also have other
features from the following list:

 * `fcKnowledge`

It is an error if the server sends a physical asset, or an asset with
any other feature, as a child of an `fcMessageBoard`.

It is an error if the server sends an `fcMessageBoard` feature for an
asset whose class is not known.


#### `fcMessage` (0x0D)

```bnf
<featuredata>       ::= <source> <timestamp> <flags> <body>
<source>            ::= <systemid>
<timestamp>         ::= <time> ; system time
<flags>             ::= <byte> ; 0x01 means "read"
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

The `<body>` is the message.

The first line of the body (everything up to the first newline) is the
heading for the message, referred to as the _subject_.

If the second line starts with the six characters `From: ` ("From"
followed by a colon and a space) then the remainder of that line is
the _sender_, a string that somehow identifies (to the player) the
source of the message. This might be a character in the story, or a
specific asset, or something else. For example, "Dr Blank" or
"Stockpile #3 in Geneva on Earth in the Sol system". Clients are
advised against attempting to map this string to actual assets in the
game world, as the strings are not unambiguous.

The rest of the string is the _text_ of the message. Newlines separate
paragraphs in the _text_.

> TODO: A future version of this protocol will change _text_ (and
> possibly _subject_ and _sender_) to support formatting, images,
> links to assets, etc.

This feature is often paired with an `fcKnowledge` feature.

This feature is typically found on assets that are children of
`fcMessageBoard` features, but they can also appear in isolation,
e.g. decorating non-virtual assets.


This feature supports the following commands:

 * `mark-read`: no additional fields. Sets the "read" bit to 0x01.
 * `mark-unread`: no additional fields. Sets the "read" bit to 0x00.

It is an error if the server sends an `fcMessage` feature for an asset
whose class is not known.


#### `fcRubblePile` (0x0E)

```bnf
<featuredata>       ::= [ <materialid> <quantity> ]* <zero32> <mass>
<quantity>          ::= <int64>
<mass>              ::= <double> // kg
```

Indicates that the asset contains, possibly among other things, a pile
of rubble.

The contents are listed as pairs of material ID and quantity (in
units). Only known materials are listed. The total mass of unknown
materials is given after the terminating zero. Materials may be listed
multiple times.

> TODO: have some command to move materials to material piles

Structures support the following command:

 * `dismantle`: No fields. Can only be sent to unowned assets or
   assets owned by the player. If there are destructors nearly (e.g. a
   population center), removes the asset, transferring any resources
   to other assets as necessary. If anything cannot be removed, the
   asset will instead be replaced by a rubble pile with those
   materials. If there's no nearby destructors, responsds with a "`no
   destructors`" error.

Clients are encouraged to implement `dismantle` in a way that
indicates cleaning up the rubble, rather than literally "dismantling"
as with `fcStructure`, despite this being the exact same feature.


#### `fcProxy` (0x0F)

```bnf
<featuredata>       ::= <assetid>
```

Includes the specified asset by reference into the current asset. For
example, a crater with a ship in the middle consists of an
`fcRubblePile` and an `fcProxy` with the ship as the asset in the
proxy feature.


#### `fcKnowledge` (0x10)

```bnf
<featuredata>       ::= [ 0x01 <assetclass> | 0x02 <material> ]* <zero8>
<material>          ::= <materialid> ; id, non-zero
                        <string>  ; icon
                        <string>  ; material name
                        <string>  ; description
                        <uint64>  ; flags, see below
                        <double>  ; mass (kg) per unit
                        <double>  ; mass (kg) per cubic meter (density)
```

A list of pieces of knowledge (asset classes, materials).

##### Asset classes

Asset classes are prefixed by the code 0x01, and consist of an asset
class id (a _signed_ non-zero 32 bit integer; may be negative), an
icon, name, and description.

Names never end with punctuation, descriptions always do.

##### Materials

Materials are prefixed by the code 0x02, and consist of a material ID
(a _signed_ non-zero 32 bit integer; may be negative), an icon, a
name, a description, and then material-specific properties. Material
IDs in the range 1..64 are ores, which can be found in assets with
`fcRegion` features and mined using assets using `fcMining` features.
Names never end with punctuation, descriptions always do.

The first property (`<flags>`) is a 64 bit bit field, whose bits have the
following meanings:

   0 (LSB): if unset, material is solid; otherwise, material is fluid
   1      : if unset, this is a bulk resource; if set, this is a component
   2      : reserved, always zero
   3      : if set, this material is pressurized
4-62      : reserved, always zero
  63 (MSB): reserved, always zero

Quantities of bulk resources should be presented in mass or volume.
Quantities of components can be presented as a count, mass, or volume.

Solid (including components) vs fluid determines how resources are
transferred and stored.

Quantities of resources (e.g. in fcStructure features) are specified
in terms of the mass per unit. For example, if Iron has a mass
per unit of 1000.0, then 10 Iron is equivalent to 10 metric tons of
Iron.

Fluids are never components (So bits 0-2 can also be read as a three
bit integer with three defined values, 000=solid, 001=fluid,
010=component).

The other two properties give the mass per unit and the mass per cubic
meter respectively.

Knowledge features may sometimes contain the same material
redundantly. Clients are encouraged to hide duplicate entries.


#### `fcResearch` (0x11)

```bnf
<featuredata>       ::= <disabled> <topics> <topic> <difficulty>
<topics>            ::= <string>* <zero32>
<topic>             ::= <string>
<difficulty>        ::= <byte>
```

For the `<disabled>` field, see below.

The <topics> strings (all of which are non-empty) represent the topics
that can be specified in `set-topic`. The topics are only given to the
asset's owner; for other dynasties, the list is empty.

The `<topic>` provides guidance regarding the currently selected area
of research for the research facility. It defaults to the empty string
(undirected research). It can be changed using the `set-topic` command
(see below). A topic does not guarantee the subject of research
(sometimes, science makes unexpected leaps), but it does provide a
push towards a particular outcome. The topic is shared with any
dynasty with internals access to the asset (and asset class knowledge).

The `<difficulty>` gives a very brief summary of the difficulty of the
ongoing research; it has a value from the following:

  0: No useful progress is being made. Maybe the current guidance
     (topic) is something this research feature is ill-equiped to
     handle, or the topic has already been exhastively researched and
     no further progress can be made in that direction. It could also
     indicate a server-side problem.

  1: The research feature is making progress towards something, but
     progress is very slow. Maybe a more specialized research facility
     would make faster progress, or providing the facility with some
     relevant samples might help, or maybe the research being pursued
     is at cross-purposes with the currently selected guidance and
     this is causing difficulties among the staff.

  2: The research feature is making active progress towards something.

(In practice, 0 means no research will happen, 1 means research is
happening but the total time it will have taken is at least one
real-world day, and 2 means the research will have taken less than a
real-world day.)

The difficulty is shared with any dynasty that can see the asset and
knows the asset class (whether or not it has internals access).

This feature supports the following command (only allowed from the
asset owner):

 * `set-topic`: One field, a string, which must match one of the given
   `<topics>`, or the empty string. The empty string selects nothing,
   leaving research undirected.

Some researches will only trigger when a particular topic is selected;
others will have their time reduced (or in some cases increased) based
on the topic.

It is an error if the server sends an `fcResearch` feature for an
asset whose class is not known.


#### `fcMining` (0x12)

```bnf
<featuredata>       ::= <maxrate> <disabled> <currentrate>
<maxrate>           ::= <double> // kg/ms
<currentrate>       ::= <double> // kg/ms
```

The asset can mine ores (materials) from the nearest ancestor asset
with an `fcRegion` feature (the source). The ores are put into assets
with an `fcOrePile` feature that are descendants of the same
`fcRegion` (the targets).

The `<disabled>` bit field has bits that specify why the feature is
not mining, if applicable. It is defined in its own section below.

The `<maxrate>` is the maximum rate of mining for this feature. The
`<currentrate>` is the current rate of mining. This is affected by
the availability of resources (see `fcRegion`) and capacity in piles
(see `fcOrePile`).

When there are no available piles, the actual _useful_ mining rate is
determined by the consumers (refineries, `fcRefining`) but the given
rate is the maximum rate; excess mining product that could not be
refined is returned to the ground (where it may be mined again).

Once a region runs out of minable materials, mining stops and the
piles are not considered an issue, even if the ore piles are full.

If not used by refining assets, the materials mined will be evident in
assets with an `fcOrePile` feature (which will have a non-zero mass
flow rate while the materials are being mined).


#### `fcOrePile` (0x13)

```bnf
<featuredata>       ::= <pilemass> <pilemassflowrate> <capacity> <materials>
<pilemass>          ::= <double> // kg
<pilemassflowrate>  ::= <double> // kg/ms
<capacity>          ::= <double> // kg
<materials>         ::= [<materialid>]* <zero32>
```

Piles of ores mined from an asset with an `fcMining` feature.
Available for use by refineries (which extract resources from ore
piles and separate them into distinct piles of pure materials for use
by factories, etc).

The capacity is the maximum mass of the pile. Capacities are
approximate. It is not unusual for a pile to cap out at slightly more
or slightly less than the rated capacity.

An empty pile has mass zero. The listed materials are those that are
recognized.

This feature supports the following command:

 * `analyze`: No fields. Returns the time of the analysis (int64),
   followed by an approximation of the total mass of material in the
   pile (double), followed by a string (see below), followed by a list
   of pairs of material IDs (int64) and masses (double) giving the
   known ores and how much of each there is. (The difference between
   the sum of these masses and the given total mass is the number of
   unknown ores.)

The string provided in the analysis is one of the following:

   ``: the empty string, indicates nothing special to report.
   
   `pile empty`: indicates that the pile is empty, so there is nothing
   to analyze.
   
   `not enough materials`: indicates that the analysis is incomplete
   because the quantities of materials being analyzed are too small.

> TODO: change this to use a binary response
> TODO: consider if other dynasties should be allowed to do this


#### `fcRegion` (0x14)

```bnf
<featuredata>       ::= <flags>
<flags>             ::= <byte> ; 0x01 means it can be mined
```

The `<flags>` bit field has eight bits interpreted as follows:

   0 (LSB): The region can still be mined.
   1      : reserved, always zero
   2      : reserved, always zero
   3      : reserved, always zero
   4      : reserved, always zero
   5      : reserved, always zero
   6      : reserved, always zero
   7 (MSB): reserved, always zero

If a region's resources are exhausted, then the first bit is reset.
This represents the region being on the verge of complete structural
collapse.


#### `fcRefining` (0x15)

```bnf
<featuredata>       ::= <ore> <maxrate> <disabled> <currentrate>
<ore>               ::= <materialid>
<maxrate>           ::= <double> // kg/ms
<currentrate>       ::= <double> // kg/ms
```

Moves a specific ore (`<ore>`) from the nearest ancestor `fcRegion`'s
`fcOrePile`s (the sources) to appropriate `fcMaterialPile`s in that
same region (the targets).

This feature is only sent if the asset class is known, and if the
asset class is known then the ore is guaranteed to be known because
its material will be included in the same knowledge feature as the
asset class, so `<ore>` will never be zero.

The `<disabled>` bit field has bits that specify why the feature is
not mining, if applicable. It is defined in its own section below.

The `<maxrate>` is the maximum rate of refining for this feature. The
`<currentrate>` is the current rate of refining. If they are not the
same, then at least one bit of `<disabled>` will be set (e.g.
insufficient staffing, insufficient inputs, insufficient space for
outputs).


#### `fcMaterialPile` (0x16)

```bnf
<featuredata>       ::= <mass> <massflowrate> <capacity> <material>
<mass>              ::= <double> // kg
<massflowrate>      ::= <double> // kg/ms
<capacity>          ::= <double> // kg
<material>          ::= <materialname> ( <materialid> | <zero32> )
```

Piles of sorted bulk materials, generated by refineries (`fcRefining`)
or factories (`fcFactory`), used by factories and to build structures
(`fcStructure`).

The `<flowrate>` gives the mass per millisecond being added (or
removed, if negative) from the pile.

This feature can be sent even if the asset class is not known. The
`<materialid>` will be zero if the _material_ is not known. (If the
asset class is known, the material is guaranteed to also be known.)


#### `fcMaterialStack` (0x17)

```bnf
<featuredata>       ::= <quantity> <flowrate> <capacity> <material>
<quantity>          ::= <int64>
<flowrate>          ::= <double>
<capacity>          ::= <int64>
<material>          ::= <materialname> ( <materialid> | <zero32> )
```

Piles of sorted non-bulk materials, generated by refineries
(`fcRefining`) or factories (`fcFactory`), used by factories and to
build structures (`fcStructure`).

The `<flowrate>` gives a number of items per millisecond being added
(or removed, if negative) from the pile.

This feature can be sent even if the asset class is not known. The
`<materialid>` will be zero if the _material_ is not known. (If the
asset class is known, the material is guaranteed to also be known.)


#### `fcGridSensor` (0x18)

```bnf
<featuredata>       ::= <disabled> [<feature>]
```

For the `<disabled>` field, see below.

Grid sensors work by walking down the tree from the nearest `fcGrid`
ancestor of the sensor. Sensors can detect any asset, regardless of
size, unless it is cloaked in some way. (It represents the ability for
populations to examine the world.)

The trailing `<feature>`, if present, is a `fcGridSensorStatus`
feature, documented next.


#### `fcGridSensorStatus` (0x19)

```bnf
<featuredata>       ::= <grid> <count>
<grid>              ::= <assetid> | <zero32>
<count>             ::= <uint32> ; number of detected assets
```

Reports the grid being scanned, and the total number of detected
nodes. The `<grid>` may be zero if no grid ancestor was found.

This feature, if present, always follows a `fcGridSensor` feature. If
there are multiple sensors, they may each have a trailing
`fcGridSensorStatus`; each status applies to the immediately
preceding sensor.


#### `fcBuilder` (0x1A)

```bnf
<featuredata>       ::= <capacity> <rate> <disabled> <structure>* <zero32>
<capacity>          ::= <uint32>
<rate>              ::= <double> ; units per millisecond
<structure>         ::= <assetid>
```

A feature that allows `fcStructure` assets to build themselves from
`fcMaterialPile` assets.

The `<capacity>` is the number of simultaneous buildings that can be
built. It will always be greater than zero.

The `<rate>` is the speed at which the feature is able to repair (or
build) structures (this rate may be limited by available resources).
It specifies the number of `<hp>` that the builder can increase a
structure by, per millisecond.

The `<disabled>` bit field has bits that specify why the feature is
not building, if applicable. It is defined in its own section below.

The list of `<structure>`s is the assets currently being built by this
asset. It is empty if `<disabled>` is non-zero.

This feature is only sent to the client if the dynasty has access to
the asset's internals.


#### `fcInternalSensor` (0x1B)

```bnf
<featuredata>       ::= <disabled> [<feature>]
```

For the `<disabled>` field, see below.

Internal sensors work by walking down the tree from the node itself.
Internal sensors can detect any asset, regardless of size, unless it
is cloaked in some way. (It represents internal cameras, crew looking
around, etc.)

The trailing `<feature>`, if present, is a `fcInternalSensorStatus`
feature, documented next.


#### `fcInternalSensorStatus` (0x1C)

```bnf
<featuredata>       ::= <count>
<count>             ::= <uint32> ; number of detected assets
```

Reports the total number of detected nodes.

This feature, if present, always follows a `fcInternalSensor` feature.
If there are multiple sensors, they may each have a trailing
`fcInternalSensorStatus`; each status applies to the immediately
preceding sensor.


#### `fcOnOff` (0x1D)

```bnf
<featuredata>       ::= <status>
<status>            ::= <byte> ; enabled (0x01) or not (0x00)
```

Represents an on/off switch on the asset.

This feature supports the following commands (only allowed from the
asset owner):

 * `enable`: No fields. Enables the asset. Returns a boolean
   indicating if anything changed.
 
 * `disable`: No fields. Disables the asset. Returns a boolean
   indicating if anything changed.

It is an error if the server sends an `fcOnOff` feature for an
asset whose class is not known.


#### `fcStaffing` (0x1E)

```bnf
<featuredata>       ::= <jobs> <staff>
<jobs>              ::= <uint32>
<staff>             ::= <uint32>
```

Represents whether staff are operating the asset. The `<jobs>`
specifies how many people are needed, the `<staff>` specifies how many
people are working it.

Staff comes from `fcPopulation` centers.

The `<jobs>` is zero if the dynasty does not have access to the
asset's internals and does not know about the asset class. Otherwise,
it is non-zero.


#### `fcAssetPile` (0x1F)

```bnf
<featuredata>       ::= <assets>* <zero32>
<assets>            ::= <assetid>
```

Child assets of a `fcAssetPile` (the `<assets>`) are piled on top of
the asset in a haphazard fashion. Each child's size will not exceed
the parent's, but their sum can.


### `fcFactory` (0x20)

```bnf
<featuredata>       ::= <inputs> <outputs> <maxrate> <configuredrate> <currentrate> <disabled>
<inputs>            ::= <materialmanifest>
<outputs>           ::= <materialmanifest>
<materialmanifest>  ::= ( <materialid> <quantity> )* <zero32>
<quantity>          ::= <uint32> ; not zero
<maxrate>           ::= <double> ; iterations/ms
<configuredrate>    ::= <double> ; iterations/ms
<currentrate>       ::= <double> ; iterations/ms
```

A feature that converts items from one type to another.

The inputs and outputs are a list of materials (without duplicates),
with non-zero quantities. Each iteration, the factory takes those
inputs from material piles/stacks, other factories, and refineries in
the region, and creates the specified outputs and puts them back into
the region.

The mass of the inputs will equal the mass of the outputs.

This feature is only sent if the asset class is known, and if the
asset class is known then the materials involed are guaranteed to be
known because they will be included in the same knowledge feature as
the asset class.

The `<currentrate>` is the lowest of the `<maxrate>`, the
`<configuredrate>`, and any rate limitations implied by `<disabled>`
(e.g. power or staffing limitations). It specifies the frequency of
factory iterations.

A factory's output may be delayed if the input cannot immediately be
found, but any such delays are offset by faster production later, such
that the average rate is the stated `<currentrate>`. (Such delays will
only be visible if the region sends an update, e.g. because another
factory is built. There is no unambiguous way for the client to
determine the state of such delayed productions, and clients are
encouraged to just act as if they did not happen, though this might
result in numbers in the UI going up and down inexplicably.)

This feature supports the following commands (only allowed from the
asset owner):

 * `set-rate`: One field, a double. Sets the `<configuredrate>`. The
   rate can be set to any value from zero to `<maxrate>`. The response
   contains no additional fields.

A factory shuts down automatically if it cannot sustain its
`<configuredrate>` (due to insufficient inputs or insufficient space
for outputs); it does not automatically throttle itself.


#### `fcSample` (0x21)

```bnf
<featuredata>       ::= <mode> <size> <mass> <massflowrate> <contents>
<mode>              ::= <byte>
<size>              ::= <double>
<mass>              ::= <double>
<massflowrate>      ::= <double>
<contents>          ::= <zero32> | <materialid> | <child>
<child>             ::= <assetid>
```

This feature represents a research sample container, and is typically
found on assets with an `fcResearch` feature.

The `<mode>` specifies what is currently held in the sample container.
The values are as follows:

   0: Nothing.
   1: Some unrefined ore.
   2: Some material.
   3: Some asset.

Modes 1 and 2 are essentially identical but allow clients to
distinguish where the sample originated.

The `<size>` gives the diameter of the sample container, in meters.
The sample container can hold items whose density allow one unit to
fit in this value cubed, in cubic meters.

The `<mass>` and `<massflowrate>` give the mass of the sample. They
are in kg and kg/ms respectively. The mass flow rate will always be
zero unless the mode is 3 and the child asset itself has a mass flow
rate, in which case it will match the child asset's mass flow rate.

The `<contents>` depend on the mode.

If the sample is an asset (mode 3), the `<contents>` is the `<child>`
that is that asset.

If the sample is unrefined ore (mode 1) or a material (mode 2), and it
has been identifed (e.g. after a successful research based on this
sample), the `<contents>` is the `<materialid>` that specifies the
exact material being stored in the sample container.

Otherwise, the sample is not identified or if the mode is zero, and
the `<contents>` value is zero.

This feature supports the following commands (only allowed from the
asset owner):

 * `sample-ore`: Only valid if `<mode>` is 0 (zero). No fields.
   Attempts to fill the sample container from the nearest ancestor
   `fcRegion`'s ore piles. Returns a boolean; true indicates a sample
   was collected, false indicates it was not.

 * `clear-sample`: Only valid if `<mode>` is 1 or 2. Attempts to
   return the sample to the appropriate pile. Returns a boolean; true
   indicates the sample was entirely discarded, false indicates that
   some amount of the sample remains.

> TODO: Support ways to add unknown materials or assets to the sample container.


### `<disabled>`

Some features can be disabled, either manually or because they're out
of resources or for some other reason; either entirely, or merely in a
manner that rate-limits the feature's normal productivity.

Such features often have a `<disabled>` bit field, which is 32 bits
wide and specifies what issues the feature is experiencing. The bits
are defined as follows.

   0 (LSB) : The asset could not find a coordinating asset. For
             example, `fcMining` and `fcRefining` features need an
             ancestor asset with an `fcRegion` feature. This can also
             be reported by `fcBuilder` (there is no feature in the
             protocol that corresponds to the one builders need, but
             it is often also present on features with `fcRegion`).
             This always entirely disables the feature.
   1       : The asset's structural integrity has not yet reached the
             minimum functional threshold (see `fcStructure` feature).
             Currently, this always entirely disables the feature.
   2       : The asset was manually disabled (see `fcOnOff` feature).
             This always entirely disables the feature.
   3       : The number of staff assigned to the asset is below the
             required number (see `fcStaffing` feature).
             This rate-limits the feature in proportion to the
             fraction of jobs staffed.
   4       : The asset requires a dynasty to own it, and does not
             have one.
             This always entirely disables the feature.
   5       : `fcFactory`: The asset is a factory configured to run at
             a speed that requires inputs faster than they are being
             generated.
             `fcRefining`: The asset is a refinery that is being
             source-limited (i.e. would go faster if more ore was
             available).
             `fcMining`: Mining has stopped because any further mining
             in this region would dangerously collapse the area.
             Either mine in another area or find another means to
             extract resources from this region.
   6       : `fcFactory`: The asset is a factory whose output has
             nowhere to go, or whose output is being generated faster
             than other assets are able to consume it. Reducing the
             factory's speed may help.
             `fcRefining`: The asset is a refinery that is being
             target-limited (i.e. would go faster if more space was
             available to store the refined material).
             `fcMining`: There is no space to store the ore being
             mined, so anything not being refined is being dumped back
             in the ground.
   7       : reserved, always zero
   ...
   31 (MSB): reserved, always zero

If any bit is set, the other bits not being set does not mean their
condition does not apply. For example, an abandoned, broken, unstaffed
gun tower may be flagged as only not having a dynasty (bit 4).
Similarly, a broken mining drill floating in space, turned off, and
unstaffed, may be flagged as only missing its coordinating asset (0),
broken (1), and disabled (2), despite also missing staff. This is
caused by server-side optimizations; once one or more reasons to
consider an asset disabled are found, the logic to determine other
reasons may be skipped.

In general, the order of features on an asset does not affect the
`<disabled>` reasoning. The exception is features, like `fcStaffing`,
that themselves can be enabled or disabled. For such features, only
features earlier in the asset will affect the `<disabled>` reasoning.


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


## `reset-rng` (`icResetRNG`)

Only available in test mode.

Fields:

 * system ID (4-byte integer)
 * state (64-bit integer)

Response is one of:

 * 0x01 byte indicating success
 * disconnection indicating failure

Resets the system's RNG to the given state.
