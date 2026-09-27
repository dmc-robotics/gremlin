import Foundation
import IOKit
import IOKit.serial

/// Lists serial ports from the IOKit registry.
public struct SerialPortDiscovery: SerialPortListing {
    // USB device property names (kUSBVendorString etc. aren't exported to Swift)
    private static let vendorIDKey = "idVendor"
    private static let productIDKey = "idProduct"
    private static let vendorNameKey = "USB Vendor Name"
    private static let productNameKey = "USB Product Name"
    private static let serialNumberKey = "USB Serial Number"

    public init() {}

    public func availablePorts() -> [SerialPortInfo] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching(kIOSerialBSDServiceValue)
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var ports: [SerialPortInfo] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path: String = property(kIOCalloutDeviceKey, of: service) else { continue }
            ports.append(SerialPortInfo(
                path: path,
                manufacturer: ancestorProperty(Self.vendorNameKey, of: service),
                product: ancestorProperty(Self.productNameKey, of: service),
                serialNumber: ancestorProperty(Self.serialNumberKey, of: service),
                vendorID: ancestorProperty(Self.vendorIDKey, of: service),
                productID: ancestorProperty(Self.productIDKey, of: service)
            ))
        }
        return ports.sorted { $0.path < $1.path }
    }

    private func property<T>(_ key: String, of service: io_object_t) -> T? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? T
    }

    /// Searches the service and its parents, where USB device properties live.
    private func ancestorProperty<T>(_ key: String, of service: io_object_t) -> T? {
        IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        ) as? T
    }
}
