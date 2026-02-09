Tech Tree
=========

ISD uses the ISD Tech Tree language (ISDTT), which is described
below, to represent the game's technology tree (which in many ways is
the core of the game).

# Files

The tech tree is in a single file, called `base.tt`.

> TODO: support includes


# Syntax

## Token and whitespace

ISDTT is a token-based language. The tokens, which are described
below, are identifiers, strings, numbers, multipliers, and symbols
(open brace, close brace, open parenthesis, close parenthesis, comma,
colon, semicolon, percentage, asterisk, slash, at).

Whitespace (spaces, newlines) separates tokens but is otherwise
ignored. Whitespace is not required for separating tokens except where
it would otherwise be ambiguous.


## Comments

Comments are C-style, either `/* ... */` block comments or `// ...`
line comments.

The start of a block comment is `/*`; the comment ends at the first
occurence of the sequence `*/` that _follows_ the opening pair (i.e.
the `/*/` is not a complete block comment, the shortest such is
`/**/`). It is an error for the file to end inside a block comment.

The start of a line comment is `//`; the comment ends at the next
newline.

Comments are treated as token separators but are otherwise ignored.
They cannot appear inside tokens (e.g. inside strings, they are
treated as part of the string data).


## Symbols

The ISDTT syntax uses following punctuation: `{` `}` `(` `)` `[` `]`
`"` `+` `-` `.` `,` `:` `;` `%` `*` `/` `@`

Braces are used to create brace blocks. Brace blocks start with `{`
and end with `}`.

The square brackets `[` `]` and quote marks `"` are used for strings.

The `+`, `-`, and '.' symbols are used for numbers.

Parentheses are used to create groups. Groups start with `(` and end
with `)`.

Commas (`,`) separate items in lists; semicolons (`;`) terminate
directives (at the top level) and fields (inside brace blocks), and
colons (`:`) separate names from values in various contexts.

The remaining symbols are used in special situations. For example, `@`
is used to separate intrinsic situations (those defined by the game
engine) from situations (facilities) defined in the tech tree. The `%,
`*`, and `/` characters are used in fields and values in various ways.
 

## Primitive data types

ISDTT supports a variety of primitive types.

### Keywords and identifiers

ISDTT has no reserved words; the language distinguishes keywords from
identifiers by context (there is no place in the grammar where both
are valid).

Identifiers must start with an ASCII letter, and may contain ASCII
letters, digits, or the hyphen character, except that if the first
character is a lowercase "x" then the next character cannot be a
digit.


### Strings

Strings have two representations, single-line and multiline.

A single-line string starts with a `"` quotation mark, and ends at the
next `"` quotation mark. A single-line string must not contain a
newline character (U+000A) but is otherwise unconstrained. There are
no escape sequences, which means a single-line string cannot contain a
`"` quotation mark or a newline. The sequence `""` represents an empty
string.

Multiline strings start with a `[` open square bracket and a newline.

Subsequent lines must all be indented by the same (non-zero) number of
space characters, followed by any characters. The first line that
starts with zero or more space characters then a `]` close square
bracket ends the string.

The first line (after the indent) must not be empty (unless it only
contains `]`).

The prefix on each line is removed. Trailing spaces on each line are
removed. Lone newlines are replaced with single space characters.
Pairs of newlines are replaced by a single newline. (Lines that start
with spaces beyond the indent found on the first line are not
removed.)

As a special case, empty strings can also be represented as `[]`,
without the otherwise required newline following the `[`.

Examples:

```
   "This is a short string."
   [
      This is a longer
      string. This is all
      line 1.

        This is line 2. It starts
      with two spaces.

      This is line 3, the last line.
   ]
```


### Numbers

Numbers optionally start with `+` or `-`, have one or more digits,
then optionally are followed by a period `.` and zero or
more digits, and finally optionally followed by an `e` or `E`, an
optional `+` or `-`, and one or more digits. The complete package is
then interpreted as a base ten number with optional fractional
component and optional base ten scale. In Perl regular expression
syntax:

   /[+-]? [0-9]+ (\. [0-9]*)? ([eE] [+-]? [0-9]+)?/x

The integer component must be in the range -9223372036854775808 to
9223372036854775807. The fractional component must not have more than
15 digits. The base ten scale number must be in the range -1022 to
1023.

An _integer_ is a number that does not have a fractional component or
a base ten scale component. (`1` is an integer; `1.0` and `1e0` are
not integers.)

Numbers are used as a part of some other primitive types:

Examples:

```
// The number one hundred and twenty three, shown a variety of ways.
// These are all exactly equivalent, except that the first one is a
// valid integer while the rest are not.
+123
123.00
123.0e-0
123e+0
1.23e2

// The value one hundredth, in two different ways:
0.01
1e-2
```


### Multipliers

An `x` followed by a number is a _multiplier_. For example, `x2` or
`x0.5`. An `x` cannot be followed by a `.` (`x.5` is not a multiplier;
indeed, it isn't valid at all; the `.` character is only valid in
ISDTT as a separator between a the integer component and fractional
component of a number.)

Examples:

```
// Double multiplier:
x2
x0.20e01

// Half mulipilier:
x0.5
x5e-1
```


### Lengths

Lengths are numbers followed by an identifier, where the identifier
specifies how the number is interpreted, as follows:

 * `LY`: Light-years (9460730472580800m)
 * `AU`: Astronomical units (149597870700m)
 * `km`: Kilometers (1000m)
 * `m`: Meters
 * `cm`: Centimeters (0.01m)
 * `mm`: Millimeters (0.001m)

Examples:

```
// Equivalent values:
1500m
1.5km

// Two light-years:
2LY
45533.5755007 AU
6.8117259e+18mm

// The distance from Earth's sun to Venus:
0.72AU
107710466904m
```


### Mass

Mass is similarly represented as a number followed by an identifier
that scales the number, as follows:

 * `t` or `Mg`: Metric tonnes (1000kg)
 * `kg`: Kilograms
 * `g`: Grams (0.001kg)
 * `mg`: Milligrams (0.000001kg)

Examples:

```
// The mass of an average apple:
0.1kg
100g
100e3 mg
```


### Quantities

Quantities (numbers of items) are represented as a (non-zero positive)
integer followed by the identifier `units`.

Items have a mass; the quantity can instead be expressed as a mass.
The quantity is rounded to the nearest integer, which must be greater
than zero.

Examples:

```
// Assuming an an apple is defined as having a mass of 0.1kg, five of them can be described as:
5 units
0.5kg
0.45kg // 4.5 rounds up to 5
512g // 5.12 rounds down to 5
```


### Values with a single unit

There are various other values that have units. Those are expressed as
a number, followed by an identifier of the specified unit.

Examples:

```
// Hit points (structural integrity)
22hp

// Staffing requirement
30 jobs

// Temperature
4000K
```


### Time

Time is represented as a number followed by an identifier describing
how to interpret the number, where the identifier is one of the
following:

 * `decades`: Decades (ten years, 315360000000ms)
 * `years`: Years (365 days, 31536000000ms)
 * `w`: Weeks (seven days, 604800000ms)
 * `d`: Days (24 hours, 86400000ms)
 * `h`: Hours (60 minutes, 3600000ms)
 * `min`: Minutes (60 seconds, 60000ms)
 * `s`: Seconds (1000ms)
 * `ms`: Milliseconds

Times are rounded to the nearest millisecond.

Examples:

```
// The following are all two hours:
2h
120min
7200s
```


### Rates

Various values are given as rates. 

Rates are a numeric value from one of the earlier categories (e.g.
number, mass, `hp`), following by a `/` character, followed by one of
the following:

 * `decade`: Per decade (ten years, 1/315360000000ms)
 * `year`: Per year (365 days, 1/31536000000ms)
 * `w`: Per week (seven days, 1/604800000ms)
 * `d`: Per day (24 hours, 1/86400000ms)
 * `h`: Per hour (60 minutes, 1/3600000ms)
 * `min`: Per minute (60 seconds, 1/60000ms)
 * `s`: Per second (1/1000ms)
 * `ms`: Per millisecond (1/1ms)

Examples:

```
// One per hour
1/h

// Two kg per day
2kg/d
```


### Build environment identifiers

Build environments are represented by keywords.

Currently, the list of build environments is hard-coded.

The currently valid keywords are `land` and `spacedock`.

> TODO: make this configurable


### Detection type identifiers

Detection types are represented by keywords.

The valid keywords are:

 * `inference`: gives inferred access to the asset.
 * `light`: gives visibility acess to the asset.
 * `class`: conveys knowledge of the asset's asset class.
 * `internals`: provides access to the asset's internals.

The `inference`, `class`, and `internals` types should not be used in
the tech tree.

The system as currently designed has room for 12 more detection types,
but they do not currently have names available to the tech tree.


## File structure

This brings us to the structure of an ISDTT file.

ISDTT files consist of research blocks, asset class blocks, and
material blocks, plus directives for declaring topics, facilities
(situations used in asset classes), and story beats.

Each of these is introduced by a keyword. Blocks end with a `{`...`}`
section, and directives end with a `;` semicolon.


### Story beats

Story beats represent groups of researches. The syntax is the
`storybeat` keyword, followed by an identifier that names the story
beat, and a `;` semicolon. The identifier must be unique among story
beats.

Examples:

```
storybeat imagined-warp;
storybeat developed-warp-engines;
storybeat need-dilthium;
```

### Facilities

Facilities are kinds of situations that can be used to specialize
research features. The syntax is the `facility` keyword, followed by
an identifier that names the facility, and a `;` semicolon. The
identifier must be unique among situations.

Examples:

```
facility astrophysics;
facility subterranean;
facility particle-accelerator;
```

### Topics

Topics are areas of research that can be selected by the user for a
research feature. 

The syntax is the keyword `topic`, a string, optionally the keyword
`requires` followed by a condition, and finally a ';' semicolon.

The string must be unique among topics.

The condition specifies the requirements for showing a topic to the
user. A topic without a condition is always visible, at every research
feature, for the entirety of the game.

The syntax for conditions is described later.

Examples:

```
topic "Quantum mechanicons" requires storybeat quanta;
topic "Entertainment";
topic "Example samples" requires situation @sample @present;
```

### Materials

Materials are what asset classes are made of.

The basic syntax of a material block is the keyword `material`, a
string giving the name of the material, and then a brace block.

The name must be unique among materials and asset classes.

The brace block contains various fields describing the material. Each
field is required and must be present exactly once.

Examples:

```
material "Wheels" {
  id: 19278;
  vaguely: "Round things";
  description: "Component for making vehicles able to move on flat surfaces.";
  icon: "wheel";
  metrics: component 0.5m weighs 5kg;
}
```


#### ID

Materials have IDs. Valid IDs expressible in the tech tree are in the
range -2147483648 to -1 and 65 to 2147483647. Negative IDs are
reserved for materials that are known to the engine. Currently there
are none. ID 0 is used to represent the lack of a material (or unknown
materials). IDs 1..64 are reserved for ores, which are defined
separately in ores.mrf (that file is processed before the `base.tt`
root tech tree, and acts as if there were 64 `material` blocks
defining IDs 1..64). IDs 65 and above are for use by the tech tree.

Each material must have a unique ID.

The syntax is `id`, a colon `:`, an integer, and a semicolon `;`.

Examples:

```
id: -1;
id: 1837;
id: 2992;
```

> TODO: add intrinsic material "Biomass" or something for when we're
> squishing people


#### Vague name

The name seen when a material isn't known is the _vague name_.

The syntax for this field is `vaguely`, a colon `:`, a string, and a
semicolon `;`. The string should not end in punctuation.

Examples:

```
vaguely: "Round things";
vaguely: "Thin flat slates with strips";
vaguely: "Sticks with spikes";
```


### Description

The next field is the description of a known material.

The syntax for this field is `description`, a colon `:`, a string, and
a semicolon `;`. The string should end with a period (or other
sentence-ending punctuation).

Examples:

```
description: "The wheels are made of rubber, and are grooved for extra friction."
description: [
  These sheets of printed circuit board provide generic implementations of
  common alogorithms for use in logic systems.
];
description: "A brush for managing hair."
```


#### Icon

The next field is the icon reference.

The syntax for this field is `icon`, a colon `:`, a string, and a
semicolon `;`. The string should identify a server-provided resource.

Specifically, the string, when interpolated into
`https://interstellar-dynasties.space/icons/{...}.png` in place of the
`{...}`, should become a URL that identifies a PNG resource.

Icon names must be no more than 32 characters long.

Icons for materials are only shared with clients once they are known,
so the names are not sensitive.

Examples:

```
icon: "wheel";
icon: "pcb"
icon: "hairbrush"
```


#### Metrics

Finally, the metrics field specifies the mass, density, and other
flags for the material.

The syntax for this field is more elaborate than the others in the
`material` block.

A metrics field must start with the keyword `metrics` and a colon.

Then, optionally, the `pressurized` keyword may be specified. If
present, it indicates that the material is under pressure.

> TODO: support the `pressurized` logic.

Then, one of `bulk`, `fluid`, or `component` must be specified.

The keyword `bulk` indicates that the material is measured in
kilograms, the keyword `fluid` indicates that the material is measured
in liters, and the keyword `component` indicates that the material is
measured in units.

> TODO: support fluids.

Then, the diameter of one unit of this material must be given, as a
length.

Then, the keyword `weighs` must be specified, followed by the mass of
one unit of this material, as a mass.

The field must end with a semicolon `;`.

Examples:

```
metrics: bulk 1m weighs 1kg;
metrics: component 10cm weighs 100g;
metrics: pressurized fluid 1m weighs 1000000kg; // TODO: support this
```


### Asset classes

Asset classes are the templates for the objects the user deals with.

The basic syntax of a material block is the keyword `asset`, a
string giving the name of the asset class, and then a brace block.

The name must be unique among materials and asset classes.

The brace block contains various fields describing the asset class.
Some fields are required, others are optional. Some may appear
multiple times.

Examples:

```
asset "City" {
  id: 2872;
  vaguely: "Settlement";
  description: "A collection of buildings and infrastructure for people to live at.";
  icon: "city";
  build: land;
  feature: Grid 6*6, 100m, land;
  feature: KnowledgeBus;
  feature: Structure size 100m, materials (
    "Roads": "Silicon" * 400t,
    "Infrastructure": "Iron" * 400t,
  ), minimum "Roads" 1500kg;
  feature: Staffing 5 jobs;
}
```


#### ID

Asset classes have IDs. Valid asset classes expressible in the tech
tree are in the range -2147483648 to -1 and 1 to 2147483647. Negative
IDs are reserved for asset classes that are known to the engine; see
below for a list of such asset classes and what they are expected to
support. ID 0 is used to represent the lack of an asset class, or an
unknown asset class. IDs 1 and above are for use by the tech tree.

Each asset class must have a unique ID.

The syntax is `id`, a colon `:`, a number, and a semicolon `;`.

Examples:

```
id: -1;
id: 1837;
id: 2992;
```

##### Intrinisc asset class IDs

The following asset IDs are defined for asset classes that the engine
requires to be defined in the tech tree. Each one requires certain
features to be present, in some cases present in a specific order.
Some features are defined such that their settings don't matter; for
these, the engine will replace them dynamically at runtime when
instantiating the asset class. Asset classes may have other features,
so long as the requirements described below are met.

Warning: these constraints are not checked when the tech tree is
parsed; violating these constraints may result in runtime crashes.

Asset class -1 is assigned to space. It must have a `SolarSystem`
feature as its first feature.

Asset class -2 is assigned to orbits. It must have an `Orbit` feature.

Asset class -3 is assigned to planetary bodies. It must have a
`PlanetaryBody` feature (whose settings don't matter) and should have
a Surface feature.

Asset class -4 is assigned to geological regions. It must have a
`Grid` feature, whose settings don't matter (the cell size is
forwarded from the settings of the Surface feature that spawned the
region, the environment is always "land"). It should additionally have
all the various physical bus features (at least `PeopleBus`,
`KnowledgeBus`, `BuilderBus`), and a `Region` feature.

Asset class -5 is assigned to craters. It must have `Proxy` and
`RubblePile` features (whose settings don't matter).

Asset class -6 is assigned to rubble piles. It must have a
`Population` feature (ideally with max population zero and the
`hidden` keyword set), and `RubblePile` and `AssetPile` features
(whose settings don't matter). They must be the first three features,
in that order.

Asset class -8 is assigned to the starting asset for the dynasty. It
must have a `DynastyOriginalColonyShip` feature, whose settings do not
matter. `Structure` and `Population` features, if present, will be
automatically filled on creation. The asset class should have some
sensor features, a `Population` feature, a `MessageBoard` feature, a
`Research` feature, and a `Knowledge` feature that points to a
research package that includes this asset class and the
`MessageBoard`'s `Message` asset class, if any.

Asset class IDs -102 to -110 are assigned to stars with categories 2
to 10 respectively. Stars must have a `Star` feature and an
`AssetName` feature; their settings do not matter.


#### Vague name

The name seen when an asset class isn't known is the _vague name_.

The syntax for this field is `vaguely`, a colon `:`, a string, and a
semicolon `;`. The string should not end in punctuation.

Examples:

```
vaguely: "A house";
vaguely: "A vehicle";
```


#### Description

The next field is the description of a known asset class.

The syntax for this field is `description`, a colon `:`, a string, and
a semicolon `;`. The string should end with a period (or other
sentence-ending punctuation).

Examples:

```
description: "This tall building is intended for communicating with the purported creator being.";
description: "This is a hole used for mining dirt from the ground.";
```


#### Icon

The next field is the icon reference.

The syntax for this field is `icon`, a colon `:`, a string, and a
semicolon `;`. The string should identify a server-provided resource.

Specifically, the string, when interpolated into
`https://interstellar-dynasties.space/icons/{...}.png` in place of the
`{...}`, should become a URL that identifies a PNG resource.

Icon names must be no more than 32 characters long.

Icons for asset classes shared with clients that can see the asset,
even if they do not know the asset class. (The placeholder icon
`unknown` is used for asset classes that are not visible but are
inferred.)

Examples:

```
icon: "house";
icon: "mining-hole"
```


#### Build environment

The `build` field takes a keyword that represents a build environment.

The syntax for this field is `build`, a colon `:`, a keyword from the
list above, and a semicolon `;`.

Examples:
```
build: land;
build: spacedock;
```


#### Features

The most interesting field for an asset class is the `feature` class.

Its syntax is the keyword `feature`, a colon `:`, an identifier that
specifies the kind of feature (see below), the settings for that
feature (varies by feature), and a semicolon `;`.

Examples:
```
feature: Grid 6*6, 100m, land;
feature: KnowledgeBus;
feature: Structure size 100m, materials (
  "Roads": "Silicon" * 400t,
  "Infrastructure": "Iron" * 400t,
), minimum "Infrastructure" 100t;
feature: Staffing 5 jobs;
```

##### `AssetName`

Names the asset.

Settings syntax: a string, giving the name of the asset.

This asset is rarely useful outside of the intrinsic asset classes
(where the engine overrides the name from the settings).

This feature must be present on the intrinsic asset classes for stars
(IDs -110 to -102).


##### `AssetPile`

Represents a disorganized pile of assets.

Settings syntax: There are no settings for this feature.

Asset class -6 (rubble piles) must have this as its third feature;
when such an asset is created, this feature is automatically
populated.

Creates an `fcAssetPile` feature.

Examples:

```
feature: AssetPile;
```


##### `Builder`

Provides the ability to build other assets.

Settings syntax:

 * The keyword `capacity`, followed by an integer.
 * A comma `,`.
 * The keyword `build`, followed by an `hp` rate.

The capacity indicates how many simultaneous assets this asset can be
responsible for building.

The rate gives the rate at which this feature can add structural
integrity points to an asset.

Creates an `fcBuilder` feature.

Examples:

```
feature: Builder capacity 1, build 1 hp/h;
feature: Builder capacity 20, build 5 hp/min;
```


##### DynastyOriginalColonyShip

Tells the client to jump to this asset. Has no effect unless populated
by the server (which only happens for asset class -8).

Settings syntax: There are no settings for this feature.

Creates an `fcPlot` feature.


##### `Factory`

Converts materials into other materials.

Settings syntax:

 * The keyword `input`.
 * One or more inputs, each of which is:
    * Optionally a number (defaults to 1 if omitted),
    * A string giving a material name,
    * A comma `,`.
 * The keyword `output`.
 * One or more outputs, each of which is:
    * Optionally a number (defaults to 1 if omitted),
    * A string giving a material name,
    * A comma `,`.
 * The keywords `max` and `throughput`.
 * A rate.

The rate gives the frequency at which the inputs are turned into the
outputs.

Creates an `fcFactory` feature.

Examples:

```
feature: Factory input "Iron", 2 "Microchips", output "Televisions", max throughput 1/h;
```


##### `Grid`

A square grid of cells into which assets may be placed.

Settings syntax:

 * An integer, an asterisk `*`, and the same integer again. This gives
   the grid dimensions (that integer is the number of cells on each
   side).
 * A comma `,`.
 * A length giving the size of the cells in the grid.
 * A comma `,`.
 * A build environment keyword.

Creates an `fcGrid` feature.

Examples:

```
feature: Grid 3*3, 10m, land;
```


##### `GridSensor`

A sensor that observes assets in its nearest ancestor grid.

Settings syntax: Comma-separated list of detection type keywords.

Assets observed by this sensor are given the specified detection types
for this feature's asset's owning dynasty.

Creates an `fcGridSensor` feature.

Examples:

```
feature: GridSensor light;
```


##### `InternalSensor`

A sensor that observes assets that are descendants of the current asset.

Settings syntax: Comma-separated list of detection type keywords.

Assets observed by this sensor are given the specified detection types
for this feature's asset's owning dynasty.

Creates an `fcInternalSensor` feature.

Examples:

```
feature: InternalSensor light;
```


##### `Knowledge`

Represents knowledge (asset classes and materials unlocked by a
research block) that a dynasty has access to.

Settings syntax: Optionally, the keywords `research` and `id` followed
by an integer. The integer must be non-zero and must match a research
ID defined in the tech tree, but this is not verified by the engine's
parser.

If the `research id` setting is omitted, the knowledge feature is
empty. This is typically used when creating the asset class that the
`MessageBoard` feature spawns (q.v.), as in that case the engine
replaces the knowledge automatically.

For the knowledge to be used by other features, an ancestor with the
`KnowledgeBus` feature must be present.

Creates an `fcKnowledge` feature.

Examples:

```
feature: Knowledge research id 123;
```


##### `KnowledgeBus`

The feature that manages internal messages related to knowledge. A
message bus should be present within any self-contained asset that has
children or features that manage knowledge, e.g. `Knowledge` and
`Research`. For example, asset class -4, the intrinsic asset class for
regions on planets, should have a knowledge bus.

Settings syntax: There are no settings for this feature.

Examples:

```
feature: KnowledgeBus;
```


##### `MaterialPile`

Represents the container for a dynasty's materials stored in a
`Region`. Such containers are specialized to a specific material, and
have a specific capacity (number of units).

Settings syntax:

 * The keyword `for`.
 * A string giving a material name.
 * A comma `,`.
 * The keyword `capacity`.
 * A quantity (which can be a mass).

Creates an `fcMaterialPile` feature if the material is `bulk` or
`fluid`, and a `fcMaterialStack` feature if the material is
`component`.

Examples:

```
feature: MaterialPile for "Iron", capacity 1000kg;
feature: MaterialPile for "Wheels", capacity 600 units;
feature: MaterialPile for "Tractors", capacity 1;
```


##### `Message`

A text message, typically used as the content of messages in a
`MessageBoard`.

Settings syntax: Optionally, the keyword `from`, an integer, the
keyword `at`, a time, a colon `:`, and a string.

If the settings are present, and the content is not replaced by a
`MessageBoard`, then the feature represents a message whose source
system is the given system ID, whose timestamp is the given time, and
whose body is the given string. The body should follow the format
described for `fcMessage` bodies.

If the settings are omitted, then the feature has no content unless it
is set dynamically. This is the expected case when defining the asset
class used by a `MessageBoard`, as it spawns an asset with the
`Message` feature class and then sets the settings dynamically.

It is an error to have a `Message` feature with no content in an asset
that is sent to the client, so the settings should only be omitted in
asset classes that are only spawned from `MessageBoard` features (this
is not verified by the parser).

Typically paired with a `Knowledge` feature.

Creates an `fcMessage` feature with the read state set to "unread".

Examples:

```
feature: Message;
feature: Message from 2097154 at 23.22 years: [
  Congratulations!

  From: Award system administrator

  You have been selected to win a gift from planet Greespam! To
  collect your gift of  TWO THOUSAND GOLD BARS  please send a ship
  to system 9874 at your earliest convenience! For your safety, do
  not send any armed ships.
];
```


##### `MessageBoard`

The feature that contains messages sent by other features.

Settings syntax: The keyword `spawns`, followed by the name of the
asset class to spawn for each message.

The asset class must have a `Message` feature (whose settings do not
matter and can be left blank, as they are always replaced by the
`MessageBoard` feature).

Creates an `fcMessageBoard` feature.

Examples:

```
feature: MessageBoard spawns "Message";
```


##### `Mining`

A feature that instructs a `Region` feature to move ores from the
ground into the asset's dynasty's ore piles (or into refineries).

Settings syntax: The keywords `max` and `throughput` followed by a
mass rate.

The given rate specifies the speed at which mass is moved in the
region.

Creates an `fcMining` feature.

Examples:

```
feature: Mining max throughput 1kg/s;
```


##### `OnOff`

A feature that allows the user to enable or disable other features on
the asset.

Settings syntax: There are no settings for this feature.

Ideally, this feature should come before other features that are
affected by it, as some features ignore later features when
determining activation.

Creates an `fcOnOff` feature.

Examples:

```
feature: OnOff;
```


##### `OrePile`

Represents the container for a dynasty's unrefined ores (mining
output) stored in a `Region`. Such containers have a specific capacity
(mass).

Settings syntax: The keywords `max` and `mass` and a mass.

The mass is the capacity of this ore pile.

Creates an `fcOrePile` feature.

Examples:

```
feature: OrePile max mass 1000kg;
```


##### `PeopleBus`

The feature that manages internal messages related to population and
staffing. A message bus should be present within any self-contained
asset that has children or features that manage people, e.g.
`Population` and `Staffing`. For example, asset class -4, the
intrinsic asset class for regions on planets, should have a people
bus.

Settings syntax: There are no settings for this feature.

Examples:

```
feature: PeopleBus;
```


##### `PlanetaryBody`

The feature that represents the mass and size of a planet. Region
features fetch their materials from their nearest ancestor asset with
a `PlanetaryBody`.

The asset class with ID -3, which represents game-generated planets in
solar systems, must have this feature. The game populates this
feature's settings automatically for those assets. For other asset
classes, they can be set manually.

Settings syntax: Optionally (and not necessary when used on asset
class -3), the following:

 * The keyword `seed`, and an integer giving the random seed for
   computing the planet's geology. (This is sent to the client.
   Currently it is not used for gameplay purposes.)
 * A comma `,`.
 * The keyword `diameter`, and a length giving the diameter of the
   planet, which is defined to be circular.
 * A comma `,`.
 * The keyword `temperature`, a number, and the keyword `K`, giving
   the temperature of the asset. (The temperature is not sent to the
   client and has no gameplay effect currently.)
 * A comma `,`.
 * The keyword `mass`, and a mass. This is the mass of the planet.
 * An open parenthesis (`(`).
 * A comma separated list of pairs of material names (strings) and
   integers in the range 1..4294967295. The integers are relative to
   each other and give the relative abundance of the given material.
   The materials must be ores, not materials defined in the tech tree.
 * An close parenthesis (`)`).
 * Optionally, a comma `,` and the keyword `can-be-dynasty-start`,
   indicating that the planet could be chosen by the dynasty game
   start logic as the initial planet. In practice this has no effect,
   since a planet with an asset configured in this way by the tech
   tree can never be in contention for game start anyway.

> TODO: Use the seed for gameplay.

> TODO: Use the temperature for gameplay.

A planetory body without settings defaults to zero values for each
aspect of the planet; this is generally not desireable unless the game
engine is replacing the settings itself.

Creates an `fcPlanetaryBody` feature.

Examples:

```
feature: PlanetaryBody seed 203853699, diameter 120km, temperature 100K, mass 6.777e17kg ("Iron" 100, "Carbon" 30, "Water" 5);
feature: PlanetaryBody seed 1000, diameter 3478.8km, temperature 300K, mass 7.347e22kg ("Silicon" 45, "Rock" 60, "Iron" 2), can-be-dynasty-start;
```


##### `Population`

Housing for a dynasty's people.

Settings syntax: the keyword `max` followed by an integer giving the
capacity of the housing. Optionally, this may be followed by a comma
`,` and the keyword `hidden`.

Asset class -6 (rubble piles) must have this as its first feature.

The feature's population is initally zero. If used for the intrinsic
asset class with ID -8, the feature's population is set to the maximum
on creation. When used with asset class -6, the population is set on
creation, but the number may vary based on the asset being dismantled
and the capacity of other assets.

The maximum population can be zero; this is the common case when
creating the intrinsic asset class with ID -6, rubble piles.

Creates an `fcPopulation` feature if the `hidden` keyword is omitted.

Examples:

```
feature: Population max 0, hidden;
feature: Population max 1, hidden;
```


##### `Proxy`

A feature than contains a single asset.

Asset class -5 (craters) must have this feature. The system populates
the proxy with the crashing asset when the crater is created.

Settings syntax: There are no settings for this feature.

Creates an `fcProxy` feature.

Examples:

```
feature: Proxy;
```


##### `Refining`

Instructs the nearest ancestor `Region` feature to move specific ores
from ore piles to material piles.

Settings syntax: Keyword `for`, a material name (string), a comma `,`,
the keywords `max` and `throughput`, and a mass rate. The material
must be an ore.

The material specifies which ore is to be moved into the material
piles (or made available to factories).

Creates an `fcRefining` feature.

Examples:

```
feature: Refining for "Iron", max throughput 1kg/s;
```


##### `Region`

The bus for material processing (as used by `Mining`, `Refining`,
`Factory`, `OrePile`, and `MaterialPile` features).

Settings syntax: The following:

  * The keywords `at` and `depth` followed by an integer in the range
    1 to 3 giving the "depth" of the region (see below).
  * A comma `,`.
  * An integer in the range 1 to 63, followed by the keywords
    `materials` (or `material` if the integer was 1).
  * Optionally: the keywords `of`, and `quantity`, followed by another
    integer in the range 1 to 9223372036854775807. (If omitted, the
    maximum value is assumed.)

The settings describe how the region should be filled of ores from the
nearest `PlanetaryBody` feature.

The depth decides which ores are in play. If the number is 3, all ores
are in play; if the number is 2, then ores marked "depth3" are
excluded, and if the number is 1, ores marked "depth2" or "depth3" are
excluded.

The next number indicates the number of materials to put in the
region. If this is smaller than the number of ores in play, then a
random subset is selected.

The final number indicates the maximum number of units of each ore to
place in the region.

This feature is expected to be present on the intrinsic asset class
-4, though this is not strictly required.

Creates an `fcRegion` feature.

Examples:

```
feature: Region at depth 2, 5 materials of quantity 1000000000000000; // (a thousand trillion units)
feature: Region at depth 1, 12 materials;
```


##### `Research`

The laboratory feature, where researches are unlocked.

Settings syntax: A comma separated list of facilities, each of which
consists of the keyword `provides` followed by a facility identifier
(defined by the `facility` directive).

An ancestor with the `KnowledgeBus` feature is necessary to track
which researches have been unlocked. This feature may also be
supported by a `Sample` feature.

Creates an `fcResearch` feature.

Examples:

```
feature: Research provides cyclotron, provides coffee;
```


##### `RubblePile`

Represents a pile of materials.

Settings syntax: There are no settings for this feature.

This feature must be part of the asset classes with IDs -5 (craters)
and -6 (rubble piles). It is populated automatically on creation by
the engine.

Asset class -6 (rubble piles) must have this as its second feature.

Creates an `fcRubble` feature.

Examples:

```
feature: RubblePile;
```


##### `Sample`

A sample container for use by a `Research` feature. When a sample is
present, creates an `@sample` situation for the sample, and an
`@sample @present` situation. When no sample is present, creates an
`@sample @empty` situation. See the situations section below.

Settings syntax: The keyword `size` followed by a length.

The length defines a volume into which samples can be placed.

Creates an `fcSample` feature.

Examples:

```
feature: Sample size 1m;
```


##### `Size`

Forces the asset to a mininum given size.

Settings syntax: A length.

Consider using the `Structure` feature instead.

Examples:

```
feature: Size 100m;
```


##### `SolarSystem`

The feature that holds the root of a system, especially if it has one
or more stars.

Settings syntax: The keywords `group` and `threshold` followed by a
length, a comma `,`, and the keywords `gravitational` `influence`
followed by the keyword `m`, a slash `/`, and the keyword `kg` (other
length and mass units are not accepted here).

The length is the maximum diameter of the system.

The second number is the gravitational influence, a made-up number for
this game that scales the hill sphere for assets at the root of a
system by their mass.

This feature must be the first feature of asset class -1.

Creates an `fcSpace` feature.

Examples:

```
feature: SolarSystem group threshold 1LY, gravitational influence 5e-15m/kg;
feature: SolarSystem group threshold 1m, gravitational influence 1m/kg;
```


##### `SpaceSensor`

A sensor that observes assets in orbits that are ancestors of this
sensor.

Settings syntax: 

 * An integer followed by the keywords `to` and `orbit`.
 * A comma `,`.
 * The keyword `up` followed by an integer, then the keyword `down`
   followed by an integer.
 * A comma `,`.
 * The keywords `min` and `size` followed by a length.
 * A comma `,`.
 * A comma-separated list of detection type keywords.

The first integer gives the number of ancestors that this asset can
traverse to find the nearest orbit.

The second integer specifies how many further ancestors the sensor
will traverse to find the root of the sensor's scanning range.

The third integer specifies how many assets down from the root the
sensor can traverse.

The length gives the minimum size of an asset for it to be detected by
the sensor.

Assets observed by this sensor are given the specified detection types
for this feature's asset's owning dynasty.

Creates an `fcSpaceSensor` feature.

Examples:

```
feature: SpaceSensor 3 to orbit, up 2 down 2, min size 3000km, light;
```


##### `Staffing`

A feature that controls whether an asset's other features are functional.

For a staffing feature to determine that an asset is functional, a
certain number of people from `Population` features must be assigned
to this feature by a `PeopleBus`.

Settings syntax: An integer followed by the keyword `jobs`.

Creates an `fcStaffing` feature.

Examples:

```
feature: Staffing 10 jobs;
```


##### `Star`

Represents the mass and size of a star.

Settings syntax: The keyword `category` followed by an integer in the
range 0 to 31, though only values 2 through 10 are functional.

The asset's mass, size, and temperature are determined from the given
category. (The temperature is used to set the temperature of
`PlanetaryBody` features in a system.)

For asset classes -110 to -102, the category should match the asset
class's defined category, as defined earlier.

Creates an `fcStar` feature.

Examples:

```
feature: Star category 5;
```


##### `Structure`

Represents the mass and size of a constructible asset.

Setting syntax:

 * The keyword `size`, followed by a length.
 * A comma `,`.
 * The keyword `materials`, followed by an open parenthesis `(`, and a
   comma-separated list of structural elements:
    * A string giving the component name.
    * A colon `:`.
    * A string giving the element name.
    * An asterisk `*`.
    * A quantity of that material.
 * A close parenthesis `)`.
 * A comma `,`.
 * The keyword `minimum` followed by one of:
    * An integer, followed by the keyword `units`.
    * A string giving one of the component names, optionally followed
      by a quantity.

The length is the diameter of the object, if it is a sphere, or its
side length, if it is a cube. (Its shape is not a gameplay element and
can only be inferred from the asset's "icon".)

The structural elements are presented in the order in which they must
be built, with foundations coming first and decorative elements last.
Materials may be listed multiple times.

The final part is the minimum structural integrity that is required
before the asset is considered functional. If it is an integer
followed by the keyword `units`, its value must be between zero and
the sum of all the numbers of units in the structural elements.
Otherwise, the string must specify one of the components (if multiple
components have the same name, it specifies the first entry with that
name), and the quantity (which may be expressed as a mass) represents
the number of units of that component (if omitted, it specifies all
the units of that component). That quantity, added to all the units of
all previous components, then forms the minimum structural integrity.

The structure starts empty, except if it is used in asset class -8, in
which case the engine fills it on creation.

To build an asset's `Structure`, another asset with a `Builder`
feature is necessary; ancestors with a `BuilderBus` and a `Region` are
required to mediate.

Creates an `fcStructure` asset.

Examples:

```
feature: Structure size 200m, materials ("Walls": "Iron" * 100t, "Defensive Perimeter": "Iron" * 50t, "Roof": "Iron" * 50t), minimum "Walls" 50t;
feature: Structure size 100m, materials (
  "Frame": "Iron" * 100t,
  "Facing": "Silicon" * 50t,
  "Decorations": "Iron" * 10t,
), minimum "Facing" 20t;
```


##### `Surface`

Represents the ground of a planetary body.

The ground is a grid, into which regions are placed.

Settings syntax:

 * The keywords `cell` and `size` followed by a length.
 * A comma `,`.
 * The keywords `region` and `size`, followed by an integer, the
   keyword `to`, and another integer. These integers must be odd; the
   first must be equal to or greater than 3; the second must be equal
   to or greater than the first.

This feature creates assets of asset class -4 on demand when necessary.

> TODO: make the spawnable asset class configurable, like `MessageBoard`.

Creates an `fcSurface` feature.

Examples:

```
feature: Surface cell size 100m, region size 3 to 5;
```


### Researches

The core concept of a technology tree in an ISDTT file is the tree of
researches. This is what creates the gameplay.

The basic syntax of a research block is the keyword `research`,
optionally the keyword `root` or the keyword `package`, and then a
brace block containing fields.

Exactly one `research` block must have the `root` keyword. This is the
root of the tech tree. This research is automatically unlocked by
every `KnowledgeBus` feature.

Research blocks can be marked with the `package` keyword. These
research blocks can be referenced from `Knowledge` features to create
assets that contain inherent information without requiring a
`Research` feature to unlock it.

Research blocks without the `root` or `package` keyword are termed
_normal_ research blocks.

The `root` research block can only contain `unlocks` fields; `package`
research blocks must contain an `id` field and can contain `unlocks`
fields, but must not contain other fields. Normal research blocks
(those without either annotation) can contain all the fields described
below.


#### ID

Researches have IDs. Valid IDs expressible in the tech tree are in the
range -2147483648 to -1, and 1 to 2147483647. Negative IDs are
reserved for researches that are known to the engine. Currently there
are none. ID 0 is used to represent the `root` research block; it is
implied by the use of that keyword and cannot be specified explicitly.
IDs 1 and above are for use by the tech tree.

This field is required exactly once in all research blocks other than
the `root` research, which must omit it.

The syntax is `id`, a colon `:`, an integer, and a semicolon `;`.

Examples:

```
id: -1;
id: 1837;
id: 2992;
```


#### Time

Researches typically take time to unlock.

This field may be specified in normal research blocks, and must be
omitted in `root` and `package` research blocks. If specified, it must
only be specified once.

The syntax is `takes`, followed by a time, and a semicolon `;`. The
time is in game time (which can vary by system, but is generally 500x
faster than real time). (There is no colon in this field's syntax.)

If omitted, the time defaults to zero milliseconds.

Examples:

```
takes 1 week;
takes 2 days;
```


#### Weight

The research being studied by a particular `Research` feature is
randomly selected. To make some researches more or less likely to be
selected, a research can be given a weight.

This field may be specified in normal research blocks, and must be
omitted in `root` and `package` research blocks. If specified, it must
only be specified once.

The syntax is `weight`, followed by an integer in the range 1 to
9223372036854775807, and a semicolon `;`. Weights are relative. (There
is no colon in this field's syntax.)

If omitted, the weight defaults to 1.

Examples:

```
weight 1;
weight 200;
```


#### Requirements

The technology tree is a tree (actually a graph) because one research
can depend on another, so that the dynasty must have researched one
technology before the other becomes available. These requirements are
described by this field.

This field must be specified exactly once in normal research blocks,
and omitted in `root` and `package` research blocks.

The syntax is `requires` followed by a condition (whose syntax is
described below), and a semicolon `;`.

Examples:

```
requires nothing;
requires storybeat science, no storybeat mining;
requires storybeat mining, situation @sample "Iron", no material "Iron";
```


#### Research bonuses

Some situations can increase or decrease the time and weight of a
research.

This field may be specified any number of times (including zero) for
normal researches, and must be omitted for `root` and `package`
research blocks.

The syntax is `with`, followed by a condition, a colon `:`, and one or
both of the following; if both are present, they must be separated by
a comma:

 * `speed` followed by a multiplier.
 * `weight` followed by a number followed by a percentage symbol `%`.

Finally, the field must end with a semicolon `;`.

If the `speed` bonus is given, it must come after a `takes` time
field. If the `weight` bonus is given, it must not come before a
`weight` field.

When the given condition applies, the bonuses are applied.

The `speed` bonus, when applied, divides the time field's time by the
given multiple. For example, a research with `takes 40w` normally
takes 40 weeks; if it has `with situation cyclotron: speed x20` and
the `Research` feature that selected this research has a `cyclotron`
feature, then it takes 2 weeks instead. (The speed may be a fraction,
to slow the progress down.)

The `weight` bonus, when applied, adds or subtracts the given
percentage of the research's weight (as specified by the `weight`
field, or 1 if there is no `weight` field) to the weight before the
random selection process. For example, `with topic "Having Fun":
weight +1000%` means that if the player selected "Having Fun" as the
research guidance for a `Research` facility, the weight of the asset
will be increased by ten times its basic weight (e.g. going from 1 to
11, or 2 to 22).

> TODO consider making the weight bonuses just constant modifiers, not
> based on the basic weight

Examples:

```
with topic "Religion": speed x2, weight +2000%;
with no situation church-support: speed x0.02;
```


#### Story

Researches result in a message to the player, represented using a
`story` field. A `story` field can also specify story beats that have
been reached, allowing several researches to all reflect the same
point in the overall story, and allowing the next part of the story to
pick up from any of them.

This field must be specified exactly once for normal researches, and
must be omitted for `root` and `package` research blocks.

The syntax is `story` and a colon `:`, followed by a comma-separated
list of storybeat keywords, followed by a string, and a semicolon `;`.
The string is a message, which should use the syntax expected for
`fcMessage` strings.

The storybeat keywords are those that this research has hit.

Examples:

```
story: mining [
  Mining

  From: Director of Research

  We've discovered how to extract dirt from the ground by digging holes.
];
```


#### Unlocks

The final field found in `research` blocks is the list of rewards that
the research unlocks.

This field can occur any number of times.

Each occurrence unlocks either a material or an asset class.

The syntax is `unlocks` followed by either the keyword `asset` and the
name of an asset, or the keyword `material` and the name of a
material, finally followed by a semicolon `;`.

Examples:

```
unlocks asset "Iron refining area";
unlocks asset "Iron pile";
unlocks material "Iron";
```


## Compound data types

### Conditions

Topics and researches can give requirements in terms of conditions,
and researches can give bonuses whose application is gated by
conditions.

Conditions are expressions that evaluate, during gameplay, to a
boolean, either indicating that the condition does match the current
situation, or indicating that it does not.

The primitive elements of a condition expression are as follows:

 * Story beats: the keyword `storybeat` followed by a storybeat
   identifier. True when the dynasty has knowledge of a research that
   hits the specified storybeat, false otherwise.

 * Materials: the keyword `material` followed by a string giving a
   material's name. True when the dynasty has knowledge of the
   material, false otherwise.

 * Asset classes: the keyword `asset` followed by a string giving an
   asset class name. True when the dynasty has knowledge of the asset
   classe, false otherwise.

 * Situations: the keyword `situation` followed by a situation (see
   below). True when the situation is in play, false otherwise.

 * Topics: the keyword `topic` followed by a string giving a topic
   name. True when the user has selected the topic as an area of
   research for the relevant `Knowledge` feature. False otherwise.
   Always false in a `topic` directive's condition.

The keyword `no` can prefix a primitive element to negate it. True
when the subexpression is false and vice versa.

These elements can be combined with two list operators:

 * Comma `,` can be used to combine elements into an "and" list; all
   elements in the list must be true for the comma-separated list as a
   whole to be true. Otherwise, it is false.

 * The keyword `or` can be used to combine elements into an "or" list;
   any one element in the list being true lets the comma-separated
   list as a whole be true. Otherwise, it is false.

Such lists can be wrapped in parentheses `(` ... `)` to form a new
element that itself can be used in a list or after the keyword `no`.

A condition can instead be merely the keyword `nothing`; this
condition is always true. (A research that `requires nothing` is
always available.)

Examples:

```
nothing // always true
(storybeat chess or storybeat monopoly), topic "Play a game"
no material "Iron", no material "Copper", (topic "Example samples" or topic "Metals"), situation @sample @present
no (storybeat "Logic" or storybeat "Computation")
no storybeat "Logic", no storybeat "Computation"
```


### Situations

The final piece of syntax in ISDTT to discuss is that of situations,
as found in conditions.

The `facility` directive, discussed earlier, defines a situation. Such
a situation is in play for any `Research` feature that provides the
facility.

In addition, every material and asset class implicitly introduces a
situation called `@sample "..."` where the string is the name of the
material or asset class. This situation is in play when a `Sample`
feature is on the same asset as, or a descendant of, the `Research`
feature. As discussed earlier, the `Sample` feature also introduces
two other situations, `@sample @present` and `@sample @empty`, that
are in play when the `Sample` feature has a sample or no sample
respectively.

The syntax for a situation, therefore is any of the following:

 * An identifier that matches one declared by `facility`.
 * An at `@` symbol, followed by the keyword `sample`, then one of:
    * A string matching a material or asset class name.
    * An `@` symbol, followed by either the keyword `empty` or the
      keyword `present`.
 
Examples:

```
research {
  // ...
  with situation @sample "Coffee": speed x5;
  requires situation coffee;
}

topic "Examine samples" requires situation @sample @present;
```
