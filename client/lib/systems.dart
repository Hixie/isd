import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'abilities/message.dart';
import 'abilities/planets.dart';
import 'abilities/population.dart';
import 'abilities/rubble.dart';
import 'abilities/sensors.dart';
import 'abilities/stars.dart';
import 'abilities/structure.dart';
import 'assets.dart';
import 'binarystream.dart';
import 'components.dart';
import 'connection.dart';
import 'containers/grid.dart';
import 'containers/messages.dart';
import 'containers/orbits.dart';
import 'containers/proxy.dart';
import 'containers/space.dart';
import 'containers/surface.dart';
import 'dynasty.dart';
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
  static const int fcSpaceSensors = 0x05;
  static const int fcSpaceSensorsStatus = 0x06;
  static const int fcPlanet = 0x07;
  static const int fcPlotControl = 0x08;
  static const int fcSurface = 0x09;
  static const int fcGrid = 0x0A;
  static const int fcPopulation = 0x0B;
  static const int fcMessageBoard = 0x0C;
  static const int fcMessage = 0x0D;
  static const int fcRubblePile = 0x0E;
  static const int fcProxy = 0x0F;
  static const int expectedVersion = fcMessage;

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
    final int id = reader.readInt32();
    if (id == 0)
      return null;
    return _assets.putIfAbsent(id, () => AssetNode(id: id));
  }

  void _send(List<Object> messageParts) {
    _connection.send(messageParts);
  }
  
  void _handleUpdate(Uint8List message) {
    final DateTime now = DateTime.timestamp();
    final BinaryStreamReader reader = BinaryStreamReader(message, _connection.codeTables);
    AssetNode? colonyShip;
    while (!reader.done) {
      final int systemID = reader.readInt32();
      final SystemNode system = _systems.putIfAbsent(systemID, () => SystemNode(id: systemID, sendCallback: _send));
      final int timeOrigin = reader.readInt64();
      final double timeFactor = reader.readDouble();
      final SpaceTime spaceTime = SpaceTime(timeOrigin, timeFactor, now);
      final int rootAssetID = reader.readInt32();
      assert(rootAssetID > 0);
      system.root = _assets.putIfAbsent(rootAssetID, () => AssetNode(id: rootAssetID, parent: system));
      final double x = reader.readDouble();
      final double y = reader.readDouble();
      system.offset = Offset(x - galaxy.diameter / 2.0, y - galaxy.diameter / 2.0);
      galaxy.addSystem(system);
      AssetNode? asset;
      while ((asset = _readAsset(reader)) != null) {
        asset!;
        final int ownerDynastyID = reader.readInt32();
        asset.ownerDynasty = ownerDynastyID > 0 ? dynastyManager.getDynasty(ownerDynastyID) : null;
        asset.mass = reader.readDouble();
        asset.size = reader.readDouble();
        asset.name = reader.readString();
        asset.icon = reader.readString();
        asset.className = reader.readString();
        asset.description = reader.readString();
        assert(asset.size > 0, 'asset reported with zero size! name=${asset.name} className=${asset.className}');
        final Set<Type> oldFeatures = asset.featureTypes;
        int featureCode;
        while ((featureCode = reader.readInt32()) != 0) {
          switch (featureCode) {
            case fcStar:
              final int starId = reader.readInt32();
              oldFeatures.remove(asset.setAbility(StarFeature(spaceTime, starId)));
            case fcPlanet:
              final int hp = reader.readInt32();
              oldFeatures.remove(asset.setAbility(PlanetFeature(spaceTime, hp)));
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
              oldFeatures.remove(asset.setContainer(SpaceFeature(children)));
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
              oldFeatures.remove(asset.setContainer(OrbitFeature(spaceTime, originChild, children)));
            case fcStructure:
              int structuralIntegrityMax = 0;
              int marker;
              final List<StructuralComponent> components = <StructuralComponent>[];
              while ((marker = reader.readInt32()) != 0) {
                assert(marker == 0xFFFFFFFF);
                final int materialCurrent = reader.readInt32();
                final int materialMax = reader.readInt32();
                structuralIntegrityMax += materialMax;
                final String componentName = reader.readString();
                final String materialName = reader.readString();
                final int materialID = reader.readInt32();
                components.add(StructuralComponent(
                  current: materialCurrent,
                  max: materialMax == 0 ? null : materialMax,
                  name: componentName.isEmpty ? null : componentName,
                  materialID: materialID,
                  description: materialName,
                ));
              }
              final int structuralIntegrityCurrent = reader.readInt32();
              final int structuralIntegrityMin = reader.readInt32();
              oldFeatures.remove(asset.setAbility(StructureFeature(
                structuralComponents: components,
                current: structuralIntegrityCurrent,
                min: structuralIntegrityMin == 0 ? null : structuralIntegrityMin,
                max: structuralIntegrityMax == 0 ? null : structuralIntegrityMax,
              )));
            case fcSpaceSensors:
              final int reach = reader.readInt32();
              final int up = reader.readInt32();
              final int down = reader.readInt32();
              final double minSize = reader.readDouble();
              AssetNode? nearestOrbit;
              AssetNode? top;
              int? count;
              reader.saveCheckpoint();
              if (!reader.done && reader.readInt32() == fcSpaceSensorsStatus) {
                nearestOrbit = _readAsset(reader);
                top = _readAsset(reader);
                count = reader.readInt32();
                reader.discardCheckpoint();
              } else {
                reader.restoreCheckpoint();
              }
              oldFeatures.remove(asset.setAbility(SpaceSensorsFeature(
                reach: reach,
                up: up,
                down: down,
                minSize: minSize,
                nearestOrbit: nearestOrbit,
                topOrbit: top,
                detectedCount: count,
              )));
            case fcPlotControl:
              final int signal = reader.readInt32();
              switch (signal) {
                case 0: ; // nothing
                case 1: assert(colonyShip == null); colonyShip = asset;
                default: throw NetworkError('Client does not support plot code 0x${signal.toRadixString(16).padLeft(8, "0")}');
              }
            case fcSurface:
              final Map<AssetNode, SurfaceParameters> children = <AssetNode, SurfaceParameters>{};
              AssetNode? child;
              while ((child = _readAsset(reader)) != null) {
                children[child!] = ();
              }
              oldFeatures.remove(asset.setContainer(SurfaceFeature(children)));
            case fcGrid:
              final double cellSize = reader.readDouble();
              final int width = reader.readInt32();
              assert(width > 0);
              final int height = reader.readInt32();
              assert(height > 0);
              final Map<AssetNode, GridParameters> children = <AssetNode, GridParameters>{};
              AssetNode? child;
              while ((child = _readAsset(reader)) != null) {
                final int x = reader.readInt32();
                final int y = reader.readInt32();
                children[child!] = (x: x, y: y);
              }
              oldFeatures.remove(asset.setContainer(GridFeature(spaceTime, cellSize, width, height, children)));
            case fcPopulation:
              final int count = reader.readInt64();
              final double happiness = reader.readDouble();
              oldFeatures.remove(asset.setAbility(PopulationFeature(
                count: count,
                happiness: happiness,
              )));
            case fcMessageBoard:
              final Map<AssetNode, MessageBoardParameters> children = <AssetNode, MessageBoardParameters>{};
              AssetNode? child;
              while ((child = _readAsset(reader)) != null) {
                children[child!] = ();
              }
              oldFeatures.remove(asset.setContainer(MessageBoardFeature(children)));
            case fcMessage:
              final int systemID = reader.readInt32();
              final int timestamp = reader.readInt64();
              final bool isRead = reader.readBool();
              final String subject = reader.readString();
              final String from = reader.readString();
              final String body = reader.readString();
              oldFeatures.remove(asset.setAbility(MessageFeature(systemID, timestamp, isRead, subject, from, body)));
            case fcRubblePile:
              oldFeatures.remove(asset.setAbility(RubblePileFeature()));
            case fcProxy:
              final AssetNode? child = _readAsset(reader);
              oldFeatures.remove(asset.setContainer(ProxyFeature(child)));
            default:
              throw NetworkError('Client does not support feature code 0x${featureCode.toRadixString(16).padLeft(8, "0")}, cannot parse server message.');
          }
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
