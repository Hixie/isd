import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'abilities/builder.dart';
import 'abilities/knowledge.dart';
import 'abilities/materialpile.dart';
import 'abilities/materialstack.dart';
import 'abilities/message.dart';
import 'abilities/mining.dart';
import 'abilities/orepile.dart';
import 'abilities/planets.dart';
import 'abilities/population.dart';
import 'abilities/refining.dart';
import 'abilities/region.dart';
import 'abilities/research.dart';
import 'abilities/rubble.dart';
import 'abilities/sensors.dart';
import 'abilities/stars.dart';
import 'abilities/structure.dart';
import 'assetclasses.dart';
import 'assets.dart';
import 'binarystream.dart';
import 'connection.dart';
import 'containers/grid.dart';
import 'containers/messages.dart';
import 'containers/orbits.dart';
import 'containers/proxy.dart';
import 'containers/space.dart';
import 'containers/surface.dart';
import 'dynasty.dart';
import 'materials.dart';
import 'nodes/galaxy.dart';
import 'nodes/system.dart';
import 'spacetime.dart';
import 'stringstream.dart';

typedef ColonyShipHandler = void Function(AssetNode colonyShip);

class SystemServer {
  SystemServer(this.url, this.token, this.galaxy, this.dynastyManager, { required this.onError, required this.onColonyShip }) {
    _connection = Connection(
      url,
      onConnected: _handleLogin,
      onBinaryMessage: _handleUpdate,
      onError: onError,
    );
  }

  final String url;
  final String token;
  final GalaxyNode galaxy;
  final DynastyManager dynastyManager;
  final ErrorCallback onError;
  final ColonyShipHandler onColonyShip;

  late final Connection _connection;

  static const int fcStar = 0x01;
  static const int fcSpace = 0x02;
  static const int fcOrbit = 0x03;
  static const int fcStructure = 0x04;
  static const int fcSpaceSensor = 0x05;
  static const int fcSpaceSensorStatus = 0x06;
  static const int fcPlanet = 0x07;
  static const int fcPlotControl = 0x08;
  static const int fcSurface = 0x09;
  static const int fcGrid = 0x0A;
  static const int fcPopulation = 0x0B;
  static const int fcMessageBoard = 0x0C;
  static const int fcMessage = 0x0D;
  static const int fcRubblePile = 0x0E;
  static const int fcProxy = 0x0F;
  static const int fcKnowledge = 0x10;
  static const int fcResearch = 0x11;
  static const int fcMining = 0x12;
  static const int fcOrePile = 0x13;
  static const int fcRegion = 0x14;
  static const int fcRefining = 0x15;
  static const int fcMaterialPile = 0x16;
  static const int fcMaterialStack = 0x17;
  static const int fcGridSensor = 0x18;
  static const int fcGridSensorStatus = 0x19;
  static const int fcBuilder = 0x1A;
  static const int expectedVersion = fcBuilder;

  Future<void> _handleLogin() async {
    final StreamReader reader = await _connection.send(<String>['login', token], queue: false);
    final int version = reader.readInt();
    if (version > expectedVersion) {
      onError(NetworkError('WARNING: Client out of date; server is on version $version but we only support version $expectedVersion'), Duration.zero);
    }
  }

  final Map<int, SystemNode> _systems = <int, SystemNode>{};
  final Map<int, AssetNode> _assets = <int, AssetNode>{};

  AssetNode? _readAsset(BinaryStreamReader reader) {
    final int id = reader.readUInt32();
    if (id == 0)
      return null;
    return _assets.putIfAbsent(id, () => AssetNode(id: id));
  }

  Future<StreamReader> _send(List<Object> messageParts) {
    return _connection.send(messageParts);
  }

  static const bool _verbose = false;

  void _handleUpdate(Uint8List message) {
    final DateTime now = DateTime.timestamp();
    final BinaryStreamReader reader = BinaryStreamReader(message, _connection.codeTables);
    AssetNode? colonyShip;
    while (!reader.done) {
      final int systemID = reader.readUInt32();
      final int currentTime = reader.readInt64();
      final double timeFactor = reader.readDouble();
      final SpaceTime spaceTime = SpaceTime(currentTime, timeFactor, now);
      final SystemNode system = _systems.putIfAbsent(systemID, () => SystemNode(
        id: systemID,
        sendCallback: _send,
        spaceTime: spaceTime,
      ));
      final int rootAssetID = reader.readUInt32();
      assert(rootAssetID > 0);
      system.root = _assets.putIfAbsent(rootAssetID, () => AssetNode(id: rootAssetID, parent: system));
      final double x = reader.readDouble();
      final double y = reader.readDouble();
      system.offset = Offset(x - galaxy.diameter / 2.0, y - galaxy.diameter / 2.0);
      galaxy.addSystem(system);
      AssetNode? asset;
      while ((asset = _readAsset(reader)) != null) {
        asset!;
        final int ownerDynastyID = reader.readUInt32();
        if (_verbose) {
          debugPrint('parsing asset $asset');
        }
        asset.ownerDynasty = ownerDynastyID > 0 ? dynastyManager.getDynasty(ownerDynastyID) : null;
        asset.mass = reader.readDouble();
        asset.massFlowRate = reader.readDouble();
        asset.timeOrigin = currentTime;
        asset.size = reader.readDouble();
        asset.name = reader.readString();
        asset.assetClassID = reader.readInt32();
        asset.icon = reader.readString();
        asset.className = reader.readString();
        asset.description = reader.readString();
        final Set<Type> oldFeatures = asset.featureTypes;
        int lastFeatureCode = 0x00;
        int featureCode;
        while ((featureCode = reader.readUInt32()) != 0) {
          if (_verbose) {
            debugPrint('  parsing feature with code $featureCode');
          }
          switch (featureCode) {
            case fcStar:
              final int starId = reader.readUInt32();
              oldFeatures.remove(asset.setFeature(StarFeature(starId)));
            case fcPlanet:
              oldFeatures.remove(asset.setFeature(PlanetFeature()));
            case fcSpace:
              final Map<AssetNode, SpaceParameters> children = <AssetNode, SpaceParameters>{};
              final AssetNode primaryChild = _readAsset(reader)!;
              children[primaryChild] = (r: 0, theta: 0);
              AssetNode? child;
              while ((child = _readAsset(reader)) != null) {
                final double distance = reader.readDouble();
                final double theta = reader.readDouble();
                children[child!] = (r: distance, theta: theta);
              }
              oldFeatures.remove(asset.setFeature(SpaceFeature(children)));
            case fcOrbit:
              final Map<AssetNode, Orbit> children = <AssetNode, Orbit>{};
              final AssetNode originChild = _readAsset(reader)!;
              AssetNode? child;
              while ((child = _readAsset(reader)) != null) {
                final double semiMajorAxis = reader.readDouble();
                final double eccentricity = reader.readDouble();
                final double omega = reader.readDouble();
                final int timeOrigin = reader.readInt64();
                final bool clockwise = reader.readBool();
                children[child!] = (a: semiMajorAxis, e: eccentricity, omega: omega, timeOrigin: timeOrigin, clockwise: clockwise);
              }
              oldFeatures.remove(asset.setFeature(OrbitFeature(
                spaceTime,
                originChild,
                children,
              )));
            case fcStructure:
              int structuralIntegrityMax = 0;
              final List<StructuralComponent> components = <StructuralComponent>[];
              int materialMax;
              while ((materialMax = reader.readUInt32()) != 0) {
                structuralIntegrityMax += materialMax;
                final String componentName = reader.readString();
                final String materialName = reader.readString();
                final int materialID = reader.readUInt32();
                components.add(StructuralComponent(
                  max: materialMax,
                  componentName: componentName.isEmpty ? null : componentName,
                  materialID: materialID,
                  materialName: materialName,
                ));
              }
              final int materialsCurrent = reader.readUInt32();
              final double materialsRate = reader.readDouble();
              final int structuralIntegrityCurrent = reader.readUInt32();
              final double structuralIntegrityRate = reader.readDouble();
              final int structuralIntegrityMin = reader.readUInt32();
              oldFeatures.remove(asset.setFeature(StructureFeature(
                structuralComponents: components,
                timeOrigin: currentTime,
                spaceTime: spaceTime,
                materialsCurrent: materialsCurrent,
                materialsRate: materialsRate,
                structuralIntegrityCurrent: structuralIntegrityCurrent,
                structuralIntegrityRate: structuralIntegrityRate,
                minIntegrity: structuralIntegrityMin == 0 ? null : structuralIntegrityMin,
                max: structuralIntegrityMax == 0 ? null : structuralIntegrityMax,
              )));
            case fcSpaceSensor:
              final int reach = reader.readUInt32();
              final int up = reader.readUInt32();
              final int down = reader.readUInt32();
              final double minSize = reader.readDouble();
              AssetNode? nearestOrbit;
              AssetNode? top;
              int? count;
              reader.saveCheckpoint();
              if (!reader.done && reader.readUInt32() == fcSpaceSensorStatus) {
                nearestOrbit = _readAsset(reader);
                top = _readAsset(reader);
                count = reader.readUInt32();
                reader.discardCheckpoint();
              } else {
                reader.restoreCheckpoint();
              }
              oldFeatures.remove(asset.setFeature(SpaceSensorFeature(
                reach: reach,
                up: up,
                down: down,
                minSize: minSize,
                nearestOrbit: nearestOrbit,
                topOrbit: top,
                detectedCount: count,
              )));
            case fcPlotControl:
              final int signal = reader.readUInt32();
              switch (signal) {
                case 0: ; // nothing
                case 1: assert(colonyShip == null); colonyShip = asset;
                default: throw NetworkError('Client does not support plot code 0x${signal.toRadixString(16).padLeft(8, "0")}');
              }
            case fcSurface:
              final Map<AssetNode, SurfaceParameters> children = <AssetNode, SurfaceParameters>{};
              AssetNode? child;
              while ((child = _readAsset(reader)) != null) {
                children[child!] = (position: Offset(reader.readDouble(), reader.readDouble()));
              }
              oldFeatures.remove(asset.setFeature(SurfaceFeature(children)));
            case fcGrid:
              final double cellSize = reader.readDouble();
              final int width = reader.readUInt32();
              assert(width > 0);
              final int height = reader.readUInt32();
              assert(height > 0);
              final Map<AssetNode, GridParameters> children = <AssetNode, GridParameters>{};
              AssetNode? child;
              while ((child = _readAsset(reader)) != null) {
                final int x = reader.readUInt32();
                final int y = reader.readUInt32();
                children[child!] = (x: x, y: y);
              }
              oldFeatures.remove(asset.setFeature(GridFeature(cellSize, width, height, children)));
            case fcPopulation:
              final int count = reader.readInt64();
              final double happiness = reader.readDouble();
              oldFeatures.remove(asset.setFeature(PopulationFeature(
                count: count,
                happiness: happiness,
              )));
            case fcMessageBoard:
              final List<AssetNode> children = <AssetNode>[];
              AssetNode? child;
              while ((child = _readAsset(reader)) != null) {
                // TODO: flip the order, the flip the order in the UI
                // so that adding children doesn't change the selected one
                children.insert(0, child!);
              }
              oldFeatures.remove(asset.setFeature(MessageBoardFeature(children)));
            case fcMessage:
              final int systemID = reader.readUInt32();
              final int timestamp = reader.readInt64();
              final bool isRead = reader.readBool();
              final String body = reader.readString();
              final List<String> paragraphs = body.split('\n').toList();
              assert(paragraphs.length >= 3);
              final String subject = paragraphs.removeAt(0);
              const String fromPrefix = 'From: ';
              assert(paragraphs.first.startsWith(fromPrefix));
              final String from = paragraphs.removeAt(0).substring(fromPrefix.length);
              oldFeatures.remove(asset.setFeature(MessageFeature(systemID, timestamp, isRead, subject, from, paragraphs.join('\n'))));
            case fcRubblePile:
              final Map<int, int> materials = <int, int>{};
              int material;
              do {
                material = reader.readInt32();
                final int quantity = reader.readInt64();
                materials[material] = quantity;
              } while (material != 0);
              oldFeatures.remove(asset.setFeature(RubblePileFeature(manifest: materials)));
            case fcProxy:
              final AssetNode? child = _readAsset(reader);
              oldFeatures.remove(asset.setFeature(ProxyFeature(child)));
            case fcKnowledge:
              final Map<int, AssetClass> assetClasses = <int, AssetClass>{};
              final Map<int, Material> materials = <int, Material>{};
              loop: while (true) {
                final int kind = reader.readInt8();
                switch (kind) {
                  case 0x00: break loop;
                  case 0x01:
                    final int id = reader.readInt32();
                    final String icon = reader.readString();
                    final String name = reader.readString();
                    final String description = reader.readString();
                    final AssetClass assetClass = AssetClass(id: id, icon: icon, name: name, description: description);
                    assetClasses[id] = assetClass;
                    system.registerAssetClass(assetClass);
                  case 0x02:
                    final int id = reader.readInt32();
                    final String icon = reader.readString();
                    final String name = reader.readString();
                    final String description = reader.readString();
                    final int flags = reader.readInt64(); // TODO: decode flags
                    final bool isFluid = (flags & 0x01) != 0;
                    final bool isComponent = (flags & 0x02) != 0;
                    assert((!isFluid) || (!isComponent));
                    final bool isPressurized = (flags & 0x08) != 0;
                    final double massPerUnit = reader.readDouble();
                    final double density = reader.readDouble();
                    final Material material = Material(
                      id: id,
                      icon: icon,
                      name: name,
                      description: description,
                      massPerUnit: massPerUnit,
                      density: density,
                      kind: isFluid ? MaterialKind.fluid : isComponent ? MaterialKind.component : MaterialKind.ore,
                      isPressurized: isPressurized,
                    );
                    materials[id] = material;
                    system.registerMaterial(material);
                }
              }
              oldFeatures.remove(asset.setFeature(KnowledgeFeature(assetClasses: assetClasses, materials: materials)));
              case fcResearch:
                final String research = reader.readString();
                oldFeatures.remove(asset.setFeature(ResearchFeature(current: research)));
              case fcMining:
                final double maxRate = reader.readDouble();
                final int flags = reader.readInt8();
                final double currentRate = reader.readDouble();
                oldFeatures.remove(asset.setFeature(MiningFeature(
                  currentRate: currentRate,
                  maxRate: maxRate,
                  enabled: flags & 0x01 > 0,
                  active: flags & 0x02 > 0,
                  sourceLimiting: flags & 0x04 > 0,
                  targetLimiting: flags & 0x08 > 0,
                )));
              case fcOrePile:
                final double pileMass = reader.readDouble();
                final double pileMassFlowRate = reader.readDouble();
                final double capacity = reader.readDouble();
                final Set<int> materials = <int>{};
                int material;
                while ((material = reader.readInt32()) != 0) {
                  materials.add(material);
                }
                oldFeatures.remove(asset.setFeature(OrePileFeature(
                  pileMass: pileMass,
                  pileMassFlowRate: pileMassFlowRate,
                  timeOrigin: currentTime,
                  spaceTime: spaceTime,
                  capacity: capacity,
                  materials: materials,
                )));
              case fcRegion:
                final int flags = reader.readInt8();
                oldFeatures.remove(asset.setFeature(RegionFeature(minable: (flags & 0x01) > 0)));
              case fcRefining:
                final int material = reader.readInt32();
                final double maxRate = reader.readDouble();
                final int flags = reader.readInt8();
                final double currentRate = reader.readDouble();
                oldFeatures.remove(asset.setFeature(RefiningFeature(
                  material: material,
                  currentRate: currentRate,
                  maxRate: maxRate,
                  enabled: flags & 0x01 > 0,
                  active: flags & 0x02 > 0,
                  sourceLimiting: flags & 0x04 > 0,
                  targetLimiting: flags & 0x08 > 0,
                )));
              case fcMaterialPile:
                final double pileMass = reader.readDouble();
                final double pileMassFlowRate = reader.readDouble();
                final double capacity = reader.readDouble();
                final String name = reader.readString();
                final int material = reader.readInt32();
                oldFeatures.remove(asset.setFeature(MaterialPileFeature(
                  pileMass: pileMass,
                  pileMassFlowRate: pileMassFlowRate,
                  timeOrigin: currentTime,
                  spaceTime: spaceTime,
                  capacity: capacity,
                  materialName: name,
                  material: material,
                )));
              case fcMaterialStack:
                final int pileQuantity = reader.readInt64();
                final double pileQuantityFlowRate = reader.readDouble();
                final int capacity = reader.readInt64();
                final String name = reader.readString();
                final int material = reader.readInt32();
                oldFeatures.remove(asset.setFeature(MaterialStackFeature(
                  pileQuantity: pileQuantity,
                  pileQuantityFlowRate: pileQuantityFlowRate,
                  timeOrigin: currentTime,
                  spaceTime: spaceTime,
                  capacity: capacity,
                  materialName: name,
                  material: material,
                )));
            case fcGridSensor:
              AssetNode? grid;
              int? count;
              reader.saveCheckpoint();
              if (!reader.done && reader.readUInt32() == fcGridSensorStatus) {
                grid = _readAsset(reader);
                count = reader.readUInt32();
                reader.discardCheckpoint();
              } else {
                reader.restoreCheckpoint();
              }
              oldFeatures.remove(asset.setFeature(GridSensorFeature(
                grid: grid,
                detectedCount: count,
              )));
            case fcBuilder:
              final int capacity = reader.readUInt32();
              final double buildRate = reader.readDouble();
              final List<AssetNode> assignedStructures = <AssetNode>[];
              AssetNode? child;
              while ((child = _readAsset(reader)) != null) {
                assignedStructures.add(child!);
              }
              oldFeatures.remove(asset.setFeature(BuilderFeature(
                capacity: capacity,
                buildRate: buildRate,
                assignedStructures: assignedStructures,
              )));
            default:
              throw NetworkError(
                'Client does not support feature code 0x${featureCode.toRadixString(16).padLeft(8, "0")}, '
                'cannot parse server message (last feature code 0x${lastFeatureCode.toRadixString(16).padLeft(2, "0")}).'
              );
          }
          lastFeatureCode = featureCode;
        }
        asset.removeFeatures(oldFeatures);
      }
      system.markAsUpdated();
      assert(() {
        system.root.walk((AssetNode node) {
          // we're just checking that the asserts in the walk methods don't fire
          return true;
        });
        return true;
      }());
    }
    if (colonyShip != null) {
      onColonyShip(colonyShip);
    }
  }

  void dispose() {
    _connection.dispose();
  }
}
