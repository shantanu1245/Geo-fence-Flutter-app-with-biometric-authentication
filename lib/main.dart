// lib/main.dart

// ignore_for_file: use_build_context_synchronously, deprecated_member_use, sort_child_properties_last, avoid_print

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geo-Fence Example',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  // Predefined target location
  final double _predefinedTargetLatitude = 18.466225;
  final double _predefinedTargetLongitude = 73.790503;

  double? _targetLatitude;
  double? _targetLongitude;
  double _distanceMeters = 0.0;
  bool _insideArea = false;
  String _statusText = 'Initializing...';
  bool _isAuthenticated = false;
  bool _isLoading = true;
  bool _authAvailable = true;
  bool _authErrorOccurred = false;

  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // Initialize the app with proper error handling
  Future<void> _initializeApp() async {
    // Set the predefined target coordinates
    _targetLatitude = _predefinedTargetLatitude;
    _targetLongitude = _predefinedTargetLongitude;
    
    // Fill the text fields with predefined coordinates
    _latController.text = _predefinedTargetLatitude.toString();
    _lngController.text = _predefinedTargetLongitude.toString();

    // Check authentication availability with error handling
    await _checkAuthAvailability();
  }

  // Check if biometric authentication is available with robust error handling
  Future<void> _checkAuthAvailability() async {
    try {
      // Check if device supports biometric authentication
      final bool canAuthenticate = await _localAuth.canCheckBiometrics;
      
      if (!canAuthenticate) {
        // If biometrics not available, skip to location tracking
        _skipAuthentication();
        return;
      }

      // Get available biometric methods
      final List<BiometricType> availableBiometrics = 
          await _localAuth.getAvailableBiometrics();

      if (availableBiometrics.isEmpty) {
        // No biometric methods available
        _skipAuthentication();
        return;
      }

      // If biometrics are available, try to authenticate
      await _authenticateWithBiometrics();
    } catch (e) {
      // Handle any platform-specific errors (like FragmentActivity requirement)
      print('Authentication availability check error: $e');
      _handleAuthError('Authentication system error: ${e.toString()}');
    }
  }

  // Handle authentication errors gracefully
  void _handleAuthError(String message) {
    setState(() {
      _authErrorOccurred = true;
      _authAvailable = false;
      _statusText = 'Authentication unavailable';
      _isLoading = false;
    });
    
    // Offer user the option to continue without authentication
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Authentication Unavailable'),
          content: Text('$message. Continue without authentication?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _skipAuthentication();
              },
              child: const Text('Continue'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    });
  }

  // Biometric authentication method with enhanced error handling
  Future<void> _authenticateWithBiometrics() async {
    try {
      final bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access location tracking',
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
          biometricOnly: false, // Changed to allow fallback to device credentials
        ),
      );

      if (authenticated) {
        setState(() {
          _isAuthenticated = true;
          _isLoading = false;
          _statusText = 'Authentication successful. Starting location tracking...';
        });
        _startLocationTracking();
      } else {
        _showAuthError('Authentication failed or cancelled');
      }
    } catch (e) {
      print('Biometric authentication error: $e');
      _handleAuthError('Authentication failed: ${e.toString()}');
    }
  }

  // Skip authentication and proceed directly to location tracking
  void _skipAuthentication() {
    setState(() {
      _isAuthenticated = true;
      _authAvailable = false;
      _isLoading = false;
      _statusText = 'Starting location tracking...';
    });
    _startLocationTracking();
  }

  // Show authentication error with retry option
  void _showAuthError(String message) {
    setState(() {
      _statusText = message;
      _isLoading = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: _reAuthenticate,
        ),
      ),
    );
  }

  // Start location tracking after successful authentication or auth skip
  Future<void> _startLocationTracking() async {
    final bool ok = await _ensurePermissions();
    if (!ok) {
      setState(() {
        _statusText = 'Location permissions required';
      });
      return;
    }

    try {
      final Position current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best
      );
      _evaluateDistanceAndState(current.latitude, current.longitude);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location error: ${e.toString()}'))
      );
    }

    _startPositionStream();
    setState(() {
      _statusText = 'Tracking location...';
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  // Helper: request/check permissions and ensure location services are enabled
  Future<bool> _ensurePermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location services disabled'),
          content: const Text('Please enable location services (GPS) and try again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK')
            ),
          ],
        ),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permission denied'),
          content: const Text('Location permission was denied. Please allow it from settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK')
            ),
          ],
        ),
      );
      return false;
    }
    if (permission == LocationPermission.deniedForever) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permission permanently denied'),
          content: const Text('Location permission is permanently denied. Please enable it from app settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK')
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  // Set the target latitude/longitude from the input fields
  Future<void> _setTargetAndStart() async {
    if (!_isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please authenticate first'))
      );
      return;
    }

    final String latText = _latController.text.trim();
    final String lngText = _lngController.text.trim();

    if (latText.isEmpty || lngText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both latitude and longitude'))
      );
      return;
    }

    double? lat = double.tryParse(latText);
    double? lng = double.tryParse(lngText);
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid latitude or longitude format'))
      );
      return;
    }

    final bool ok = await _ensurePermissions();
    if (!ok) return;

    setState(() {
      _targetLatitude = lat;
      _targetLongitude = lng;
      _statusText = 'Target set: (${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
    });

    _startLocationTracking();
  }

  // Start listening to continuous position updates
  void _startPositionStream() {
    _positionStream?.cancel();

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1,
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings
    ).listen(
      (Position position) {
        _evaluateDistanceAndState(position.latitude, position.longitude);
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location error: ${error.toString()}'))
        );
      },
    );
  }

  // Calculate distance between current position and target, update UI state
  void _evaluateDistanceAndState(double currentLat, double currentLng) {
    if (_targetLatitude == null || _targetLongitude == null) return;

    double meters = Geolocator.distanceBetween(
      currentLat, currentLng, _targetLatitude!, _targetLongitude!
    );
    bool inside = meters <= 100.0;

    setState(() {
      _distanceMeters = meters;
      _insideArea = inside;
      _statusText = inside ? 
        'You are inside the 100 m radius' : 
        'You are outside the 100 m radius';
    });
  }

  // Stop continuous location updates
  void _stopPositionStream() {
    _positionStream?.cancel();
    _positionStream = null;
    setState(() {
      _statusText = 'Location tracking stopped';
    });
  }

  // Re-authenticate user
  Future<void> _reAuthenticate() async {
    setState(() {
      _isLoading = true;
    });
    await _checkAuthAvailability();
  }

  // Format distance for display
  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(1)} m';
    } else {
      double km = meters / 1000.0;
      return '${km.toStringAsFixed(3)} km';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geo-fence (100 m) Demo'),
        actions: [
          if (!_isAuthenticated && _authAvailable && !_authErrorOccurred)
            IconButton(
              icon: const Icon(Icons.fingerprint),
              onPressed: _reAuthenticate,
              tooltip: 'Authenticate',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing...'),
                ],
              ),
            )
          : !_isAuthenticated
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _authErrorOccurred ? Icons.error : Icons.fingerprint,
                        size: 64,
                        color: _authErrorOccurred ? Colors.orange : Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _authErrorOccurred ? Colors.orange : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_authErrorOccurred)
                        ElevatedButton(
                          onPressed: _reAuthenticate,
                          child: const Text('Try Again'),
                        ),
                      if (_authErrorOccurred)
                        Column(
                          children: [
                            ElevatedButton(
                              onPressed: _skipAuthentication,
                              child: const Text('Continue Without Auth'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _reAuthenticate,
                              child: const Text('Retry Authentication'),
                            ),
                          ],
                        ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_authAvailable)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            border: Border.all(color: Colors.orange),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _authErrorOccurred 
                                ? 'Authentication unavailable - running in limited mode'
                                : 'Running without authentication',
                            style: const TextStyle(color: Colors.orange),
                          ),
                        ),
                      const SizedBox(height: 16),
                      const Text('Set main location (latitude / longitude):'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _latController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          border: OutlineInputBorder()
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _lngController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          border: OutlineInputBorder()
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: _setTargetAndStart,
                            child: const Text('Update Location'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _stopPositionStream,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey
                            ),
                            child: const Text('Stop Listening'),
                          ),
                        ],
                      ),
                      const Divider(height: 30),
                      Text('Status: $_statusText'),
                      const SizedBox(height: 8),
                      Text('Distance: ${_formatDistance(_distanceMeters)}'),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _insideArea ? 'You are IN the area' : 'You are OUT of the area',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                              Icon(
                                _insideArea ? Icons.check_circle : Icons.location_off,
                                color: _insideArea ? Colors.green : Colors.red,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('- Predefined target location: 18.466225, 73.790503'),
                      const Text('- Best tested on a real device (GPS) for accurate results.'),
                      const Text('- In emulator, simulate location via Extended Controls or adb commands.'),
                    ],
                  ),
                ),
      floatingActionButton: _isAuthenticated ? FloatingActionButton(
        onPressed: () async {
          try {
            if (!await _ensurePermissions()) return;
            final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.best
            );
            _latController.text = pos.latitude.toString();
            _lngController.text = pos.longitude.toString();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Filled current location into fields'))
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error getting location: ${e.toString()}'))
            );
          }
        },
        child: const Icon(Icons.my_location),
        tooltip: 'Use current device location',
      ) : null,
    );
  }
}