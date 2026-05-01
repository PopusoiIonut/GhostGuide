import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var manager = GeofenceManager()
    
    // A regional state for MapKit
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.5072, longitude: 0.1276),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. The Map Radar background
            Map(coordinateRegion: $mapRegion, showsUserLocation: true, annotationItems: manager.activePOIs) { poi in
                MapAnnotation(coordinate: poi.coordinate) {
                    Circle()
                        .fill(Color.purple.opacity(0.4))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle().stroke(Color.purple, lineWidth: 2)
                        )
                        .overlay(
                            VStack {
                                Image(systemName: "headphones")
                                    .foregroundColor(.white)
                                Text(poi.title)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        )
                }
            }
            .ignoresSafeArea()
            .edgesIgnoringSafeArea(.all)
            .colorScheme(.dark) // Force dark mode for radar look
            
            // 2. Control Console
            VStack {
                Spacer()
                
                if let playing = manager.currentlyPlaying {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(.purple)
                            .imageScale(.large)
                        Text("Whispering: \(playing)")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                    .padding(.bottom, 10)
                }
                
                Button(action: {
                    if manager.isTracking {
                        manager.stopTracking()
                    } else {
                        manager.startTracking()
                    }
                }) {
                    Text(manager.isTracking ? "DISABLE RADAR" : "ACTIVATE RADAR")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                        .background(manager.isTracking ? Color.red : Color.purple)
                        .cornerRadius(16)
                        .shadow(color: manager.isTracking ? .red.opacity(0.5) : .purple.opacity(0.5), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onReceive(manager.$userLocation) { location in
            if let location = location {
                withAnimation {
                    mapRegion.center = location
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
