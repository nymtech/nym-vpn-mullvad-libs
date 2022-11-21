//
//  DNSProxyProvider.swift
//  DNSProxy
//
//  Created by pronebird on 09/11/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import MullvadLogging
import NetworkExtension

class DNSProxyProvider: NEDNSProxyProvider {
    private let logger: Logger
    private let connectionQueue = DispatchQueue(label: "DNSProxyProvider-connQ")
    private let pathMonitor = NWPathMonitor()

    override init() {
        let pid = ProcessInfo.processInfo.processIdentifier

        var metadata = Logger.Metadata()
        metadata["pid"] = .string("\(pid)")

        initLoggingSystem(
            bundleIdentifier: Bundle.main.bundleIdentifier!,
            applicationGroupIdentifier: ApplicationConfiguration.securityGroupIdentifier,
            metadata: metadata
        )

        logger = Logger(label: "DNSProxyProvider")

        logger.debug("Init!")

        super.init()
    }

    override func startProxy(
        options: [String: Any]? = nil,
        completionHandler: @escaping (Error?) -> Void
    ) {
        logger.debug("Start DNS proxy.")
        pathMonitor.pathUpdateHandler = { _ in
            // Do nothing.
        }
        pathMonitor.start(queue: connectionQueue)

        completionHandler(nil)
    }

    override func stopProxy(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        logger.debug("Stop DNS proxy.")

        pathMonitor.cancel()

        completionHandler()
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }

    override func wake() {
        // Add code here to wake up.
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        if let tcpFlow = flow as? NEAppProxyTCPFlow {
            logger.debug("Got new TCP flow to remote: \(tcpFlow.remoteEndpoint)")
            return true
        } else {
            logger.debug("Got unknown flow.")
            return false
        }
    }

    override func handleNewUDPFlow(
        _ flow: NEAppProxyUDPFlow,
        initialRemoteEndpoint remoteEndpoint: NWEndpoint
    ) -> Bool {
        var interfaceName = "(unknown)"
        var isBound = "(unknown)"
        var resolvedHost = "(unknown)"

        if #available(iOSApplicationExtension 13.4, *) {
            if let networkInterface = flow.networkInterface {
                let namePointer = nw_interface_get_name(networkInterface)
                interfaceName = String(cString: namePointer)
            }
        }

        if #available(iOSApplicationExtension 14.3, *) {
            isBound = "\(flow.isBound)"
            if let remoteHostname = flow.remoteHostname {
                resolvedHost = remoteHostname
            }
        }

        let localEndpointString = flow.localEndpoint.map { "\($0)" } ?? "(null)"

        logger.debug(
            """
            Got new UDP flow with local endpoint: \(localEndpointString), \
            to \(remoteEndpoint) via \(interfaceName) (isBound: \(isBound)), \
            resolving \(resolvedHost), \
            app \(flow.metaData.sourceAppSigningIdentifier)
            """
        )

        guard let remoteEndpoint = remoteEndpoint as? NWHostEndpoint,
              let remoteAddress = remoteEndpoint.ipAddress,
              let remotePort = UInt16(remoteEndpoint.port) else { return false }

        do {
            let routeResult = try resolveRoute(to: remoteAddress)
            let requiredInterface = pathMonitor.currentPath.availableInterfaces.first { interface in
                return interface.name == routeResult.interfaceName
            }

            if "\(remoteAddress)".hasPrefix("10.64.0."),
               !routeResult.interfaceName.hasPrefix("utun")
            {
                logger.error("Trying to route 10.64.0.x outside the tunnel.")
            }

            /*
             if #available(iOSApplicationExtension 13.4, *) {
                if let inner = requiredInterface?.inner {
                    // If the flow's data is transported using a different interface, this property
                    // should be set to that interface.
                    flow.networkInterface = inner
                }
            }
             */

            flow.open(withLocalEndpoint: flow.localEndpoint as? NWHostEndpoint) { error in
                if let error = error {
                    self.logger.error(error: error, message: "Failed to open the flow.")
                    return
                }

                self.startUDPConnection(
                    ipAddress: remoteAddress,
                    port: remotePort,
                    requiredInterface: requiredInterface,
                    flow: flow
                )
            }
        } catch {
            logger.error(error: error, message: "Failed to resolve route.")

            let refuseError = NEAppProxyFlowError(.refused)
            flow.closeReadWithError(refuseError)
            flow.closeWriteWithError(refuseError)
        }

        return true
    }

    private func startUDPConnection(
        ipAddress: IPAddress,
        port: UInt16,
        requiredInterface: NWInterface?,
        flow: NEAppProxyUDPFlow
    ) {
        let connection = UDPConnectionProxy(
            ipAddress: ipAddress,
            port: port,
            requiredInterface: requiredInterface,
            flow: flow,
            queue: connectionQueue
        )

        connection.start()
    }
}

private extension NWHostEndpoint {
    var ipAddress: IPAddress? {
        return IPv4Address(hostname) ?? IPv6Address(hostname)
    }
}

private extension NWInterface {
    var inner: nw_interface_t? {
        let mirror = Mirror(reflecting: self)
        let nw = mirror.children.first { $0.label == "nw" }

        return nw?.value as? nw_interface_t
    }
}
