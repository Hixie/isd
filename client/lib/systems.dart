import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'abilities/planets.dart';
import 'abilities/sensors.dart';
import 'abilities/stars.dart';
import 'abilities/structure.dart';
import 'assets.dart';
import 'binarystream.dart';
import 'components.dart';
import 'connection.dart';
import 'containers/grid.dart';
import 'containers/orbits.dart';
import 'containers/space.dart';
import 'containers/surface.dart';
import 'nodes/galaxy.dart';
import 'nodes/system.dart';
import 'spacetime.dart';
import 'stringstream.dart';

typedef ColonyShipHandler = void Function(AssetNode colonyShip);

class SystemServer {
  SystemServer(this.url, this.token, this.galaxy, { required this.onError, required this.onColonyShip }) {
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
  static const int expectedVersion = fcGrid;

  Future<void> _handleLogin() async {
    final StreamReader reader = await _connection.send(<String>['login', token], queue: false);
    final int version = reader.readInt();
    if (version > expectedVersion) {
      onError(NetworkError('WARNING: Client out of date; server is on version $version but we only support version $expectedVersion'), Duration.zero);
    }
    _systems.values.forEach(galaxy.removeSystem);
    _systems.clear();
    _assets.clear();
  }

  final Map<int, SystemNode> _systems = <int, SystemNode>{};
  final Map<int, AssetNode> _assets = <int, AssetNode>{};

  AssetNode _readAsset(BinaryStreamReader reader) {
    final int id = reader.readInt64();
    assert(id != 0);
    return _assets.putIfAbsent(id, () => AssetNode(id: id));
  }

  AssetNode? _readAssetOrNull(BinaryStreamReader reader) {
    final int id = reader.readInt64();
    if (id == 0)
      return null;
    return _assets.putIfAbsent(id, () => AssetNode(id: id));
  }

  void _handleUpdate(Uint8List message) {
    final DateTime now = DateTime.timestamp();
    final BinaryStreamReader reader = BinaryStreamReader(message, _connection.codeTables);
    AssetNode? colonyShip;
    while (!reader.done) {
      final int systemID = reader.readInt32();
      final SystemNode system = _systems.putIfAbsent(systemID, () => SystemNode(id: systemID));
      final int timeOrigin = reader.readInt64();
      final double timeFactor = reader.readDouble();
      final SpaceTime spaceTime = SpaceTime(timeOrigin, timeFactor, now);
      final int rootAssetID = reader.readInt64();
      assert(rootAssetID > 0);
      system.root = _assets.putIfAbsent(rootAssetID, () => AssetNode(id: rootAssetID, parent: system));
      final double x = reader.readDouble();
      final double y = reader.readDouble();
      system.offset = Offset(x - galaxy.diameter / 2.0, y - galaxy.diameter / 2.0);
      galaxy.addSystem(system);
      int assetID;
      while ((assetID = reader.readInt64()) != 0) {
        final AssetNode asset = _assets.putIfAbsent(assetID, () => AssetNode(id: assetID));
        asset.ownerDynasty = galaxy.getDynasty(reader.readInt32());
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
              final AssetNode primaryChild = _readAsset(reader);
              children[primaryChild] = (r: 0, theta: 0);
              final int childCount = reader.readInt32();
              for (int index = 0; index < childCount; index += 1) {
                final double distance = reader.readDouble();
                final double theta = reader.readDouble();
                final AssetNode child = _readAsset(reader);
                children[child] = (r: distance, theta: theta);
              }
              oldFeatures.remove(asset.setContainer(SpaceFeature(children)));
            case fcOrbit:
              final Map<AssetNode, Orbit> children = <AssetNode, Orbit>{};
              final AssetNode originChild = _readAsset(reader);
              final int childCount = reader.readInt32();
              for (int index = 0; index < childCount; index += 1) {
                final double semiMajorAxis = reader.readDouble();
                final double eccentricity = reader.readDouble();
                final double omega = reader.readDouble();
                final int timeOrigin = reader.readInt64();
                final bool clockwise = reader.readBool();
                final AssetNode child = _readAsset(reader);
                children[child] = (a: semiMajorAxis, e: eccentricity, omega: omega, timeOrigin: timeOrigin, clockwise: clockwise);
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
              final int regionCount = reader.readInt32();
              final Map<AssetNode, SurfaceParameters> children = <AssetNode, SurfaceParameters>{};
              for (int index = 0; index < regionCount; index += 1) {
                final AssetNode child = _readAsset(reader);
                children[child] = ();
              }
              oldFeatures.remove(asset.setContainer(SurfaceFeature(children)));
            case fcGrid:
              final double cellSize = reader.readDouble();
              final int width = reader.readInt32();
              assert(width > 0);
              final int height = reader.readInt32();
              assert(height > 0);
              final Map<AssetNode, GridParameters> children = <AssetNode, GridParameters>{};
              for (int y = 0; y < height; y += 1) {
                for (int x = 0; x < width; x += 1) {
                  final AssetNode? child = _readAssetOrNull(reader);
                  if (child != null)
                    children[child] = (x: x, y: y);
                }
              }
              oldFeatures.remove(asset.setContainer(GridFeature(cellSize, width, height, children)));
            default:
              throw NetworkError('Client does not support feature code 0x${featureCode.toRadixString(16).padLeft(8, "0")}');
          }
        }
        asset.removeFeatures(oldFeatures);
      }
    }
    if (colonyShip != null) {
      onColonyShip(colonyShip);
    }
  }

  void dispose() {
    _connection.dispose();
  }
}
