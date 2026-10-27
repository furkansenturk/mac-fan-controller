import Foundation

/// "Tell me when this temperature goes above this value."
public struct TemperatureAlert: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var source: TemperatureSource
    public var thresholdCelsius: Double
    public var isEnabled: Bool

    public init(id: UUID = UUID(), source: TemperatureSource, thresholdCelsius: Double, isEnabled: Bool = true) {
        self.id = id
        self.source = source
        self.thresholdCelsius = thresholdCelsius
        self.isEnabled = isEnabled
    }

    /// After firing, an alert fires again only once the temperature has fallen this far below the threshold,
    /// so a reading that hovers around it doesn't send a stream of notifications.
    public static let rearmBelowCelsius = 5.0

    public enum Transition: Equatable {
        /// Crossed the threshold while armed: notify.
        case fire
        /// Cooled down far enough: the next crossing notifies again.
        case rearm
    }

    /// What a new reading means for an alert that is `armed` (hasn't fired since it last cooled down).
    public func transition(celsius: Double, armed: Bool) -> Transition? {
        if armed, celsius > thresholdCelsius { return .fire }
        if !armed, celsius <= thresholdCelsius - Self.rearmBelowCelsius { return .rearm }
        return nil
    }
}
