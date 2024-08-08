import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'binarystream.dart';
import 'components.dart';
import 'connection.dart';
import 'features.dart';
import 'features/galaxy.dart';
import 'features/space.dart';
import 'stringstream.dart';
import 'world.dart';

class SystemServer {
  SystemServer(this.url, this.token, this.galaxy, { required this.onError }) {
    _connection = Connection(
      url,
      onConnected: _handleLogin,
      onBinaryMessage: _handleUpdate,
      onError: onError,
    );
  }

  final String url;
  final String token;
  final ErrorCallback onError;
  final GalaxyNode galaxy;
  
  late final Connection _connection;

  static const int fcStar = 1;
  static const int fcSpace = 2;
  static const int fcOrbit = 3;
  static const int fcStructure = 4;
  static const int fcSpaceSensors = 5;
  static const int fcSpaceSensorsStatus = 6;
  static const int expectedVersion = fcSpaceSensorsStatus;
  
  Future<void> _handleLogin() async {
    final StreamReader reader = await _connection.send(<String>['login', token], queue: false);
    final int version = reader.readInt();
    if (version > expectedVersion) {
      onError(NetworkError('WARNING: Client out of date; server is on version $version but we only support version $expectedVersion'), Duration.zero);
    }
  }

  final Map<int, SystemNode> _systems = <int, SystemNode>{};
  final Map<int, AssetNode> _assets = <int, AssetNode>{};

  AssetNode _readAsset(BinaryStreamReader reader) {
    final int id = reader.readInt64();
    assert(id != 0);
    return _assets.putIfAbsent(id, () => AssetNode(id));
  }
  
  void _handleUpdate(Uint8List message) {
    final reader = BinaryStreamReader(message, _connection.codeTables);
    while (!reader.done) {
      final int systemID = reader.readInt32();
      final SystemNode system = _systems.putIfAbsent(systemID, () => SystemNode(systemID));
      final int timeOrigin = reader.readInt64();
      final double timeFactor = reader.readDouble();
      final int rootAssetID = reader.readInt64();
      system.root = _assets.putIfAbsent(rootAssetID, () => AssetNode(rootAssetID));
      final double x = reader.readDouble();
      final double y = reader.readDouble();
      system.offset = Offset(x, y);
      galaxy.addSystem(system);
      int assetID;
      while ((assetID = reader.readInt64()) != 0) {
        final AssetNode asset = _assets.putIfAbsent(assetID, () => AssetNode(assetID));
        asset.ownerDynasty = galaxy.getDynasty(reader.readInt32());
        asset.mass = reader.readDouble();
        asset.size = reader.readDouble();
        asset.name = reader.readString();
        asset.icon = reader.readString();
        asset.className = reader.readString();
        asset.description = reader.readString();
        final Set<Type> oldFeatures = asset.featureTypes;
        int featureCode;
        while ((featureCode = reader.readInt32()) != 0) {
          switch (featureCode) {
            case fcStar:
              final int starId = reader.readInt32();
              oldFeatures.remove(asset.setAbility(StarFeature(asset, starId)));
            case fcSpace:
              final Set<SpaceChild> children = {};
              final AssetNode primaryChild = _readAsset(reader);
              children.add((r: 0, theta: 0, child: primaryChild));
              final int childCount = reader.readInt32();
              for (var index = 0; index < childCount; index += 1) {
                final double distance = reader.readDouble();
                final double theta = reader.readDouble();
                final AssetNode child = _readAsset(reader);
                children.add((r: distance, theta: theta, child: child));
              }
              oldFeatures.remove(asset.setContainer(SpaceFeature(asset, children)));
            case fcOrbit:
              final Set<Orbit> children = {};
              final AssetNode originChild = _readAsset(reader);
              children.add((a: 0, e: 0, theta: 0, omega: 0, child: originChild));
              final int childCount = reader.readInt32();
              for (var index = 0; index < childCount; index += 1) {
                final double semiMajorAxis = reader.readDouble();
                final double eccentricity = reader.readDouble();
                final double thetaZero = reader.readDouble();
                final double omega = reader.readDouble();
                final AssetNode child = _readAsset(reader);
                children.add((a: semiMajorAxis, e: eccentricity, theta: thetaZero, omega: omega, child: child));
              }
              oldFeatures.remove(asset.setContainer(OrbitFeature(asset, timeOrigin, timeFactor, children)));
            case fcStructure:
              var structuralIntegrityMax = 0;
              int marker;
              final List<StructuralComponent> components = [];
              while ((marker = reader.readInt32()) != 0) {
                assert(marker == 0xFFFFFFFF);
                final int materialCurrent = reader.readInt32();
                final int materialMax = reader.readInt32();
                structuralIntegrityMax += materialMax;
                final String componentName = reader.readString();
                final String materialName = reader.readString();
                final Material material = reader.readObject<Material>(Material.new);
                components.add(StructuralComponent(
                  current: materialCurrent,
                  max: materialMax == 0 ? null : materialMax,
                  name: componentName.isEmpty ? null : componentName,
                  material: material,
                  description: materialName,
                ));
              }
              final int structuralIntegrityCurrent = reader.readInt32();
              final int structuralIntegrityMin = reader.readInt32();
              oldFeatures.remove(asset.setAbility(StructureFeature(
                parent: asset,
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
                parent: asset,
                reach: reach,
                up: up,
                down: down,
                minSize: minSize,
                nearestOrbit: nearestOrbit,
                topOrbit: top,
                detectedCount: count,
              )));
            default:
              throw NetworkError('Client does not support feature code 0x${featureCode.toRadixString(16).padLeft(8, "0")}');
          }
        }
        asset.removeFeatures(oldFeatures);
      }
    }
  }

  void dispose() {
    _connection.dispose();
  }
}
