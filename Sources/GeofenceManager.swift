import Foundation
import CoreLocation
import AVFoundation
import UIKit
import Combine
import SwiftUI
import UserNotifications

struct POI: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let coordinate: CLLocationCoordinate2D
}

class GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let synthesizer = AVSpeechSynthesizer()
    private var ambiencePlayer: AVAudioPlayer?
    
    @Published var activePOIs: [POI] = []
    @Published var isTracking = false
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var currentlyPlaying: String?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // We no longer require persistent location updates in the background.
        // Geofencing is handled by the system and doesn't need this flag.
        locationManager.allowsBackgroundLocationUpdates = false
        
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            // Using .duckOthers ensures that our background ambience will get quieter 
            // when the TTS speaks, and it also plays nicely with other apps.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    func startTracking() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
        playAmbience()
        isTracking = true
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        activePOIs.removeAll()
        stopAmbience()
        isTracking = false
    }
    
    private func playAmbience() {
        // Look for 'ambience.mp3' or 'ambience.wav' in the main bundle
        guard let url = Bundle.main.url(forResource: "ambience", withExtension: "mp3") ?? 
                        Bundle.main.url(forResource: "ambience", withExtension: "wav") else {
            print("Ambience file not found. Please add 'ambience.mp3' to project assets.")
            return
        }
        
        do {
            ambiencePlayer = try AVAudioPlayer(contentsOf: url)
            ambiencePlayer?.numberOfLoops = -1 // Infinite loop
            ambiencePlayer?.volume = 0.3 // Low volume background hum
            ambiencePlayer?.prepareToPlay()
            ambiencePlayer?.play()
            print("Background ambience started.")
        } catch {
            print("Failed to play ambience: \(error.localizedDescription)")
        }
    }
    
    private func stopAmbience() {
        ambiencePlayer?.stop()
        ambiencePlayer = nil
        print("Background ambience stopped.")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.userLocation = location.coordinate
            
            // If we don't have active POIs yet, fetch them for this location
            if self.activePOIs.isEmpty {
                self.fetchWikipediaPOIs(near: location.coordinate)
            }
        }
    }
    
    private func fetchWikipediaPOIs(near coordinate: CLLocationCoordinate2D) {
        // Use generator to fetch summaries and coordinates simultaneously
        let urlString = "https://en.wikipedia.org/w/api.php?action=query&generator=geosearch&ggsradius=10000&ggscoord=\(coordinate.latitude)|\(coordinate.longitude)&ggslimit=10&prop=extracts|coordinates&exintro=1&explaintext=1&format=json"
        
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let query = json["query"] as? [String: Any],
                   let pages = query["pages"] as? [String: [String: Any]] {
                    
                    var newPOIs: [POI] = []
                    
                    for (_, page) in pages {
                        if let title = page["title"] as? String,
                           let extract = page["extract"] as? String,
                           let coordsArray = page["coordinates"] as? [[String: Any]],
                           let firstCoord = coordsArray.first,
                           let lat = firstCoord["lat"] as? Double,
                           let lon = firstCoord["lon"] as? Double {
                            
                            // To keep audio tours brief and punchy, only read the first two sentences
                            let sentences = extract.components(separatedBy: ". ")
                            let shortSummary = sentences.prefix(2).joined(separator: ". ") + (sentences.count > 2 ? "." : "")
                                                        
                            let poiCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                            
                            let poi = POI(title: title, summary: shortSummary, coordinate: poiCoordinate)
                            newPOIs.append(poi)
                            
                            self.setupGeofence(for: poi)
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.activePOIs = newPOIs
                    }
                }
            } catch {
                print("Error parsing Wikipedia data: \(error)")
            }
        }.resume()
    }
    
    private func setupGeofence(for poi: POI) {
        let region = CLCircularRegion(center: poi.coordinate, radius: 100.0, identifier: poi.title)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        locationManager.startMonitoring(for: region)
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        
        // Find matching POI
        if let poi = activePOIs.first(where: { $0.title == circularRegion.identifier }) {
            sendNotification(for: poi)
            speak(poi: poi)
        }
    }
    
    private func sendNotification(for poi: POI) {
        let content = UNMutableNotificationContent()
        content.title = "Ghost Sighted: \(poi.title)"
        content.body = "You have entered a haunted area. Listening to the story..."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func speak(poi: POI) {
        DispatchQueue.main.async {
            self.currentlyPlaying = poi.title
        }
        
        // Ensure audio session is active
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to reactivate audio session: \(error)")
        }
        
        let utterance = AVSpeechUtterance(string: poi.summary)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        
        synthesizer.speak(utterance)
        
        // Haptic feedback to alert user we are talking
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
