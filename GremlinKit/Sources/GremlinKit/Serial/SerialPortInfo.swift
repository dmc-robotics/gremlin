import Foundation

public struct SerialPortInfo: Identifiable, Hashable, Sendable {
    /// Callout device path (`/dev/cu.*`), which opens without waiting for carrier detect.
    public var path: String
    public var manufacturer: String?
    public var product: String?
    public var serialNumber: String?
    public var vendorID: Int?
    public var productID: Int?

    public init(
        path: String,
        manufacturer: String? = nil,
        product: String? = nil,
        serialNumber: String? = nil,
        vendorID: Int? = nil,
        productID: Int? = nil
    ) {
        self.path = path
        self.manufacturer = manufacturer
        self.product = product
        self.serialNumber = serialNumber
        self.vendorID = vendorID
        self.productID = productID
    }

    public var id: String { path }

    public var displayName: String {
        guard let manufacturer, !manufacturer.isEmpty else { return path }
        return "\(path) - \(manufacturer)"
    }

    /// USB vendor IDs of Arduino boards and common USB-serial chips
    /// (Arduino, FTDI, WCH, Silicon Labs, Prolific, Microchip, SparkFun, PJRC/Teensy).
    private static let arduinoVendorIDs: Set<Int> = [0x2341, 0x0403, 0x1A86, 0x10C4, 0x067B, 0x04D8, 0x1B4F, 0x16C0]
    // Computed because Regex isn't Sendable; literals are compiled at build time, so this is cheap.
    private static var arduinoManufacturer: Regex<Substring> {
        /arduino|ftdi|silicon labs|wch|prolific|ch340|ch341|cp210/.ignoresCase()
    }
    private static var arduinoPath: Regex<Substring> { /usbmodem|usbserial/.ignoresCase() }

    public var isLikelyArduino: Bool {
        if let vendorID, Self.arduinoVendorIDs.contains(vendorID) { return true }
        if let manufacturer, manufacturer.contains(Self.arduinoManufacturer) { return true }
        return path.contains(Self.arduinoPath)
    }

    /// Likely Arduino ports first, otherwise keeping the original order.
    public static func sortedLikelyArduinoFirst(_ ports: [SerialPortInfo]) -> [SerialPortInfo] {
        ports.filter(\.isLikelyArduino) + ports.filter { !$0.isLikelyArduino }
    }
}

/// Lists serial ports. A protocol so app models can be tested with a fake.
public protocol SerialPortListing: Sendable {
    func availablePorts() -> [SerialPortInfo]
}
