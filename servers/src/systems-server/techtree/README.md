Tech Tree Format
================

# Syntax

## Strings

Strings are either `"..."` (without escapes) or delimited using `[`...`]` as follows:

```
   [
      line 1
      line 1
      line 1

      line 2
      line 2

      line 3
      line 3
   ]
```

Newlines are turned into spaces unless there are two of them; and the
prefix indent on each line is stripped.

## Lengths

Lengths are numbers followed by "m", "cm", or "mm" to specify the unit.


# Topics

The values you can pick from a research building.

```
topic "Topic Name" requires a, b, c;
```

These are identified by the string. They unlock when the specified researches are unlocked.


# Researches

```
research techid {
  id: 1; // if this is 0, it must be followed by "(root)", as in, "id: 0 (root);"
  takes 1 week;
  weight 1;
  requires othertechid, moretechid; // must be present unless id=0
  with "Topic Name": time -50%, weight +50%;
  with techid: time -50%, weight +50%;
  without techid: time +200%, weight -90%;
  rewards asset classid;
  rewards material "Material";
  rewards "message"; // max one string reward per research
}
```

There must always be one research with ID 0.


# Materials

```
material {
  id: 123456; // must be >64
  name: "Material Name" ("Vague Name");
  description: "Description.";
  icon: "iconname";
  metrics: component 1m weighs 1kg;
  // metrics: fluid 1m weighs 1kg;
  // metrics: pressurized fluid 1m weighs 1kg;
  // metrics: bulk 1m weighs 1kg;
}
```


# Asset classes

```
class classid {
  id: 123456;
  name: "Asset Class Name" ("Vague Name");
  description: "Description.";
  icon: "iconname";
  build: land; // or spacedock
  feature: TBuilderFeatureClass capacity 1, build 1 hp/h;
  feature: TFoodBusFeatureClass;
  feature: TFoodGenerationFeatureClass size 10;
  feature: TKnowledgeBusFeatureClass;
  feature: TKnowledgeFeatureClass;
  feature: TMaterialPileFeatureClass for "Iron", capacity 10kg; // or 10 units
  feature: TMessageBoardFeatureClass spawns classid;
  feature: TMessageFeatureClass;
  feature: TMiningFeatureClass max throughput 1kg/s;
  feature: TOnOffFeatureClass;
  feature: TOrePileFeatureClass max mass 1kg;
  feature: TParameterizedGridFeatureClass 3x3, 4m, land; // or spacedock
  feature: TPeopleBusFeatureClass;
  feature: TPopulationFeatureClass max 1, hidden;
  feature: TProxyFeatureClass;
  feature: TRefiningFeatureClass for "Iron", max throughput 1kg/s;
  feature: TRegionFeatureClass at depth 2, 5 materials of quantity 1000000000000000; // (a thousand trillion units) ("of quantity ..." is optional, defaults to max)
  feature: TResearchFeatureClass provides "topic1", provides "topic2";
  feature: TSizeFeatureClass 100m;
  feature: TSolarSystemFeatureClass group threshold 1m, gravitational influence 1;
  feature: TSpaceSensorFeatureClass 1 to orbit, up 2 down 3, min size 4, inference, light, class, internals;
  feature: TStaffingFeatureClass 10 jobs;
  feature: TStructureFeatureClass size 100m, materials (
    "Component Name 1": "Material Name 1" * 1000,
    "Component Name 2": "Material Name 2" * 1000,
  ), minimum 1500;
}
```

The following features are not supported:

 * TAssetNameFeatureClass
 * TDynastyOriginalColonyShipFeatureClass
 * TGenericGridFeatureClass (use TParameterizedGridFeatureClass)
 * TOrbitFeatureClass
 * TPlanetaryBodyFeatureClass
 * TRubblePileFeatureClass
 * TStarFeatureClass
 * TSurfaceFeatureClass
