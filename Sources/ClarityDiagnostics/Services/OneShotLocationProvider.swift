import ClarityCore
import CoreLocation
import Foundation

@MainActor
final class OneShotLocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
  enum State: Equatable {
    case idle
    case requesting
    case located(GeographicCoordinate)
    case denied
    case failed(String)

    var label: String {
      switch self {
      case .idle: "Not requested"
      case .requesting: "Requesting location…"
      case .located(let coordinate):
        "Using coarse location \(coordinate.latitude.formatted(.number.precision(.fractionLength(1)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(1))))"
      case .denied: "Location access denied"
      case .failed(let message): message
      }
    }
  }

  var onStateChange: ((State) -> Void)?
  private(set) var state: State = .idle {
    didSet { onStateChange?(state) }
  }

  private let manager: CLLocationManager

  override init() {
    manager = CLLocationManager()
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
  }

  func requestLocation() {
    switch manager.authorizationStatus {
    case .notDetermined:
      state = .requesting
      manager.requestWhenInUseAuthorization()
    case .authorized, .authorizedAlways:
      state = .requesting
      manager.requestLocation()
    case .denied, .restricted:
      state = .denied
    @unknown default:
      state = .failed("Location authorization is unavailable.")
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    switch manager.authorizationStatus {
    case .authorized, .authorizedAlways:
      state = .requesting
      manager.requestLocation()
    case .denied, .restricted:
      state = .denied
    case .notDetermined:
      break
    @unknown default:
      state = .failed("Location authorization is unavailable.")
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      state = .failed("Core Location returned no location.")
      return
    }
    let coordinate = GeographicCoordinate(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude
    )
    .coarsened()
    state = .located(coordinate)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    if let locationError = error as? CLError, locationError.code == .denied {
      state = .denied
    } else {
      state = .failed("Could not determine location: \(error.localizedDescription)")
    }
  }
}
