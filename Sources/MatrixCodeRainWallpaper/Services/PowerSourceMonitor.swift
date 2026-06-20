import Foundation
import IOKit.ps

enum PowerSourceMonitor {
    final class Observation {
        private final class CallbackBox {
            let callback: () -> Void

            init(callback: @escaping () -> Void) {
                self.callback = callback
            }
        }

        private var source: CFRunLoopSource?
        private var context: UnsafeMutableRawPointer?

        init?(callback: @escaping () -> Void) {
            let box = CallbackBox(callback: callback)
            let context = Unmanaged.passRetained(box).toOpaque()

            guard let source = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else {
                    return
                }

                Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue().callback()
            }, context)?.takeRetainedValue() else {
                Unmanaged<CallbackBox>.fromOpaque(context).release()
                return nil
            }

            self.context = context
            self.source = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        deinit {
            invalidate()
        }

        func invalidate() {
            if let source {
                CFRunLoopSourceInvalidate(source)
            }

            source = nil

            if let context {
                Unmanaged<CallbackBox>.fromOpaque(context).release()
            }

            context = nil
        }
    }

    static func observeChanges(_ callback: @escaping () -> Void) -> Observation? {
        Observation(callback: callback)
    }

    static var isPowerAdapterConnected: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

        guard !sources.isEmpty else {
            return true
        }

        var foundPowerSourceState = false

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)
                    .takeUnretainedValue() as? [String: Any],
                let state = description[kIOPSPowerSourceStateKey] as? String
            else {
                continue
            }

            foundPowerSourceState = true

            if state == kIOPSACPowerValue {
                return true
            }
        }

        return !foundPowerSourceState
    }
}
