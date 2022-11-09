//
//  UDPConnectionProxy.swift
//  DNSProxy
//
//  Created by pronebird on 15/11/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadLogging
import Network
import class NetworkExtension.NEAppProxyUDPFlow
import class NetworkExtension.NWHostEndpoint

final class UDPConnectionProxy {
    private let logger: Logger
    private let hostEndpoint: NWHostEndpoint
    private let queue: DispatchQueue
    private let flow: NEAppProxyUDPFlow
    private let connection: NWConnection

    private var error: Error?
    private var isFinished = false

    init(
        ipAddress: IPAddress,
        port: UInt16,
        requiredInterface: NWInterface?,
        flow: NEAppProxyUDPFlow,
        queue: DispatchQueue
    ) {
        logger = Logger(label: "UDPConnectionProxy.\(nextConnectionId())")
        hostEndpoint = NWHostEndpoint(hostname: "\(ipAddress)", port: "\(port)")

        let parameters = NWParameters.udp
        parameters.requiredInterface = requiredInterface

        connection = NWConnection(
            host: NWEndpoint.Host("\(ipAddress)"),
            port: NWEndpoint.Port(integerLiteral: port),
            using: parameters
        )

        self.queue = queue
        self.flow = flow
    }

    func start() {
        queue.async {
            self.startNoQueue()
        }
    }

    private func finish(error: Error?) {
        queue.async {
            guard !self.isFinished else { return }

            self.isFinished = true
            self.error = error

            self.connection.stateUpdateHandler = nil
            self.connection.pathUpdateHandler = nil
            self.connection.cancel()

            self.flow.closeReadWithError(error)
            self.flow.closeWriteWithError(error)
        }
    }

    private func startNoQueue() {
        connection.stateUpdateHandler = { state in
            self.handleStateChange(state)
        }
        connection.pathUpdateHandler = { path in
            let remoteEndpoint = path.remoteEndpoint.map { "\($0)" } ?? "(nil)"

            self.logger.debug(
                """
                Path for remote endpoint: \(remoteEndpoint) via \
                \(path.availableInterfaces.map { $0.name })
                """
            )
        }

        connection.start(queue: queue)

        logger.debug("Start UDP connection to \(hostEndpoint).")
    }

    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            sendData()
            receiveData()

        case let .failed(error):
            logger.error(error: error, message: "UDP connection failed.")
            finish(error: error)

        case .cancelled:
            finish(error: nil)

        default:
            break
        }
    }

    private func sendData() {
        guard !isFinished else { return }

        flow.readDatagrams { data, endpoints, error in
            if let error = error {
                self.logger.error(error: error, message: "Failed to read datagrams from UDP flow.")
                self.finish(error: error)
                return
            }

            // If the datagrams and remoteEndpoints arrays are non-nil but are empty, then no more
            // datagrams can be subsequently read from the flow.
            guard let data = data, let endpoints = endpoints, !data.isEmpty else {
                self.logger.debug("Reached the end of inbound flow.")
                return
            }

            let dispatchGroup = DispatchGroup()

            for (index, payload) in data.enumerated() {
                dispatchGroup.enter()

                #if DEBUG
                self.logger.debug(
                    """
                    Received datagram (\(payload.count) bytes) from \(endpoints[index])
                    """
                )
                #endif

                self.connection.send(content: payload, completion: .contentProcessed { error in
                    if let error = error {
                        self.logger.error(error: error, message: "Failed to send data.")
                        self.finish(error: nil)
                    }

                    dispatchGroup.leave()
                })
            }

            dispatchGroup.notify(queue: self.queue) {
                self.sendData()
            }
        }
    }

    private func receiveData() {
        connection.receiveMessage { completeContent, contentContext, isComplete, error in
            if let error = error {
                self.logger.error(error: error, message: "Failed to receive data.")
                self.finish(error: error)
                return
            }

            if let completeContent = completeContent {
                self.flow.writeDatagrams([completeContent], sentBy: [self.hostEndpoint]) { error in
                    if let error = error {
                        self.logger.error(
                            error: error,
                            message: "Failed to write diagrams into UDP flow."
                        )
                        self.finish(error: error)
                        return
                    }

                    if isComplete {
                        self.logger.debug("UDP connection is complete.")
                        self.finish(error: nil)
                    } else {
                        self.receiveData()
                    }
                }
            } else if isComplete {
                self.logger.debug("UDP connection is complete.")
                self.finish(error: nil)
            } else {
                // Must never happen
                self.logger.debug("receiveMessage() returned no content and isComplete is false.")
            }
        }
    }
}

// MARK: - Connection counter

private let connectionIdLock = NSLock()
private var connectionId: UInt64 = 0

private func nextConnectionId() -> UInt64 {
    connectionIdLock.lock()
    defer { connectionIdLock.unlock() }

    let (partialValue, overflow) = connectionId.addingReportingOverflow(1)

    if overflow {
        connectionId = 1
    } else {
        connectionId = partialValue
    }

    return connectionId
}
