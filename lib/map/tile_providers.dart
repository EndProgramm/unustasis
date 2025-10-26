import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:unustasis/domain/saved_scooter.dart';
import 'package:url_launcher/url_launcher.dart';

TileLayer get openStreetMapTileLayer => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'dev.fleaflet.flutter_map.example',
      // Use the recommended flutter_map_cancellable_tile_provider package to
      // support the cancellation of loading tiles.
      tileProvider: CancellableNetworkTileProvider(),
    );


class AnimatedMapControllerPage extends StatefulWidget {
  static const String route = '/map_controller_animated';

  final SavedScooter savedScooter;
  const AnimatedMapControllerPage({ super.key, required this.savedScooter });


  @override
  AnimatedMapControllerPageState createState() =>
      AnimatedMapControllerPageState();
}


enum GpsState {
    off,
    searching,
    fixEstablished,
    error,
}

class Standort {
    final String zustand;
    final double lat;
    final double lon;
    final double alt;
    final double rich;
    final double tempo;
    final String zeit;

    Standort({required this.lat, required this.lon, required this.zustand, required this.alt, required this.rich, required this.tempo, required this.zeit});

    factory Standort.fromJson(Map<String, dynamic> json) {
      return Standort(
          zustand: json['zustand'],
          lat: double.parse(json['lat'].toString()),
          lon: double.parse(json['lon'].toString()),
          alt: double.parse(json['alt'].toString()),
          rich: double.parse(json['rich'].toString()),
          tempo: double.parse(json['tempo'].toString()),
          zeit: json['zeit'],
        );
    }
}

class AnimatedMapControllerPageState extends State<AnimatedMapControllerPage>
    with TickerProviderStateMixin {
  static const _startedId = 'AnimatedMapController#MoveStarted';
  static const _inProgressId = 'AnimatedMapController#MoveInProgress';
  static const _finishedId = 'AnimatedMapController#MoveFinished';
  final log = Logger("ScooterMap");

  late final Timer _everySecond;
  Key _scooterPosUpdated = UniqueKey();
  LatLng? position;
  double heading = 0;
  bool headingKnown = false;
  Color posUpdateButtonColor = Colors.blueAccent;

  @override
  void initState() {
    super.initState();

    position = widget.savedScooter.lastLocation;

    // defines a timer
    _everySecond = Timer.periodic(Duration(seconds: 15), (Timer t) {
      setState(() {
        updatePos();
      });
    });
  }

  void updatePos() {
    log.info("requesting Scooter pos");

    var future = fetchPos();

    future.then((value) {
      log.info("Got Standort { zustand: ${value.zustand}, lat: ${value.lat}, lon: ${value.lon}, alt: ${value.alt}, rich: ${value.rich}, tempo: ${value.tempo}, zeit: ${value.zeit} } from Server");
      position = LatLng(value.lat, value.lon);
      heading = value.rich;
      if (value.rich != 0) {
        headingKnown = true;
      } else {
        headingKnown = false;
      }
      _animatedMapMove(LatLng(value.lat, value.lon), 17);
      posUpdateButtonColor = Colors.lightGreen;
    }).catchError((error) {
      log.log(Level.WARNING, "Failed to get position with error: $error");
      posUpdateButtonColor = Colors.redAccent;
    });

    _scooterPosUpdated = UniqueKey();
  }

  Future<Standort> fetchPos() async {
    final response = await http.get(
      Uri.parse('https://dawn.egnetwork.de:44443/dawn/api/v1/scooter/1/pos/now'),
    );

    if (response.statusCode == 200) {
      // If the server did return a 200 OK response,
      // then parse the JSON.
      var parsed = Standort.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      return parsed;
    } else {
      // If the server did not return a 200 OK response,
      // then throw an exception.
      throw Exception('Failed to load Standort');
    }
  }

  final mapController = MapController();

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    // Create some tweens. These serve to split up the transition from one location to another.
    // In our case, we want to split the transition be<tween> our current map center and the destination.
    final camera = mapController.camera;
    final latTween = Tween<double>(
        begin: camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(
        begin: camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom);

    // Create a animation controller that has a duration and a TickerProvider.
    final controller = AnimationController(
        duration: const Duration(milliseconds: 500), vsync: this);
    // The animation determines what path the animation will take. You can try different Curves values, although I found
    // fastOutSlowIn to be my favorite.
    final Animation<double> animation =
        CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);

    // Note this method of encoding the target destination is a workaround.
    // When proper animated movement is supported (see #1263) we should be able
    // to detect an appropriate animated movement event which contains the
    // target zoom/center.
    final startIdWithTarget =
        '$_startedId#${destLocation.latitude},${destLocation.longitude},$destZoom';
    bool hasTriggeredMove = false;

    controller.addListener(() {
      final String id;
      if (animation.value == 1.0) {
        id = _finishedId;
      } else if (!hasTriggeredMove) {
        id = startIdWithTarget;
      } else {
        id = _inProgressId;
      }

      hasTriggeredMove |= mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
        id: id,
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
      } else if (status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return LimitedBox(
        maxHeight: 200,
        child:
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: position!,
            initialZoom: 17,
          ),
          children: [
            openStreetMapTileLayer,
            RichAttributionWidget(
              popupInitialDisplayDuration: const Duration(seconds: 2),
              animationConfig: const ScaleRAWA(),
              showFlutterMapAttribution: false,
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () async => launchUrl(
                    Uri.parse('https://openstreetmap.org/copyright'),
                  ),
                ),
              ],
            ),
            AnimatedLocationMarkerLayer(
              key: _scooterPosUpdated,
              position: LocationMarkerPosition(latitude: position!.latitude, longitude: position!.longitude, accuracy: 30),
              heading: LocationMarkerHeading(heading: heading, accuracy: headingKnown ? 0.5 : 10 ),
            ),
            Align(
              alignment: AttributionAlignment.bottomLeft.real,
              child: IconButton(onPressed: updatePos, icon: Icon(Icons.refresh), color: posUpdateButtonColor,),
            ),
          ],
        ),
      );
  }
}

final _animatedMoveTileUpdateTransformer =
    TileUpdateTransformer.fromHandlers(handleData: (updateEvent, sink) {
  final mapEvent = updateEvent.mapEvent;

  final id = mapEvent is MapEventMove ? mapEvent.id : null;
  if (id?.startsWith(AnimatedMapControllerPageState._startedId) ?? false) {
    final parts = id!.split('#')[2].split(',');
    final lat = double.parse(parts[0]);
    final lon = double.parse(parts[1]);
    final zoom = double.parse(parts[2]);

    // When animated movement starts load tiles at the target location and do
    // not prune. Disabling pruning means existing tiles will remain visible
    // whilst animating.
    sink.add(
      updateEvent.loadOnly(
        loadCenterOverride: LatLng(lat, lon),
        loadZoomOverride: zoom,
      ),
    );
  } else if (id == AnimatedMapControllerPageState._inProgressId) {
    // Do not prune or load whilst animating so that any existing tiles remain
    // visible. A smarter implementation may start pruning once we are close to
    // the target zoom/location.
  } else if (id == AnimatedMapControllerPageState._finishedId) {
    // We already prefetched the tiles when animation started so just prune.
    sink.add(updateEvent.pruneOnly());
  } else {
    sink.add(updateEvent);
  }
});
