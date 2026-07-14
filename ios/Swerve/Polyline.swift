import Foundation
import MapKit

enum Polyline {
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var latitude = 0
        var longitude = 0

        func decodeValue() -> Int? {
            var result = 0
            var shift = 0
            while index < encoded.endIndex {
                let byte = Int(encoded[index].asciiValue ?? 63) - 63
                index = encoded.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 { return (result & 1) == 1 ? ~(result >> 1) : result >> 1 }
            }
            return nil
        }

        while index < encoded.endIndex, let latDelta = decodeValue(), let lngDelta = decodeValue() {
            latitude += latDelta
            longitude += lngDelta
            coordinates.append(.init(latitude: Double(latitude) / 100_000, longitude: Double(longitude) / 100_000))
        }
        return coordinates
    }
}
