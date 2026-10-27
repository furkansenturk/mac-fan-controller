import IOKit

/// The internal SSD's model name from the I/O Registry, e.g. "APPLE SSD AP0512R", so its temperature
/// can carry the same name System Information shows.
enum InternalDisk {
    /// Apple Silicon first, then T2 Intel Macs.
    private static let deviceClasses = ["IOEmbeddedNVMeBlockDevice", "IONVMeBlockStorageDevice"]

    static func productName() -> String? {
        for deviceClass in deviceClasses {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(deviceClass), &iterator) ==
                KERN_SUCCESS
            else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                let property = IORegistryEntryCreateCFProperty(
                    service,
                    "Device Characteristics" as CFString,
                    kCFAllocatorDefault,
                    0
                )
                if let characteristics = property?.takeRetainedValue() as? [String: Any],
                   let name = (characteristics["Product Name"] as? String)?.trimmingCharacters(in: .whitespaces),
                   !name.isEmpty
                {
                    return name
                }
            }
        }
        return nil
    }
}
