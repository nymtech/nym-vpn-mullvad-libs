//
//  TransportProvider.swift
//  MullvadTransport
//
//  Created by Marco Nikic on 2023-05-25.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Logging
import MullvadREST
import MullvadTypes
import RelayCache
import RelaySelector

public final class TransportProvider: RESTTransport {
    private let urlSessionTransport: URLSessionTransport
    private let relayCache: RelayCache
    private let logger = Logger(label: "TransportProvider")
    private let addressCache: REST.AddressCache
    private var transportStrategy: TransportStrategy

    /// In memory cache of the current mode of transport
    private var currentTransport: RESTTransport?
    /// Protects internal state when multiple requests are made in parallel
    private let parallelRequestsMutex = NSLock()

    /// The cached shadowsocks configuration
    private let shadowsocksCache: ShadowsocksConfigurationCache
    /// Forces getting a new shadowsocks configuration for the next request when set to `true`
    private var skipShadowsocksCache = false

    public init(
        urlSessionTransport: URLSessionTransport,
        relayCache: RelayCache,
        addressCache: REST.AddressCache,
        transportStrategy: TransportStrategy = .init(),
        shadowsocksCache: ShadowsocksConfigurationCache
    ) {
        self.urlSessionTransport = urlSessionTransport
        self.relayCache = relayCache
        self.addressCache = addressCache
        self.transportStrategy = transportStrategy
        self.shadowsocksCache = shadowsocksCache
    }

    // MARK: -

    // MARK: RESTTransport implementation

    private func transport() -> RESTTransport {
        urlSessionTransport
    }

    private func shadowsocksTransport() -> RESTTransport? {
        do {
            let shadowsocksConfiguration = try shadowsocksConfiguration()

            let shadowsocksURLSession = urlSessionTransport.urlSession
            let shadowsocksTransport = URLSessionShadowsocksTransport(
                urlSession: shadowsocksURLSession,
                shadowsocksConfiguration: shadowsocksConfiguration,
                addressCache: addressCache
            )

            return shadowsocksTransport
        } catch {
            logger.error(error: error)
        }
        return nil
    }

    // MARK: -

    // MARK: RESTTransport implementation

    public var name: String { currentTransport?.name ?? "TransportProvider" }

    public func sendRequest(
        _ request: URLRequest,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> Cancellable {
        parallelRequestsMutex.lock()
        defer {
            parallelRequestsMutex.unlock()
        }

        let currentStrategy = transportStrategy
        guard let transport = makeTransport() else { return AnyCancellable() }
        let transportSwitchErrors: [URLError.Code] = [
            .cancelled,
            .notConnectedToInternet,
            .internationalRoamingOff,
            .callIsActive,
        ]

        let failureCompletionHandler: (Data?, URLResponse?, Error?)
            -> Void = { [weak self] data, response, maybeError in
                guard let self else { return }
                if let error = maybeError as? URLError,
                   transportSwitchErrors.contains(error.code) == false
                {
                    parallelRequestsMutex.lock()
                    // Guarantee that the transport strategy switches mode only once when parallel requests fail at
                    // the same time.
                    if currentStrategy == transportStrategy {
                        transportStrategy.didFail()
                        currentTransport = nil
                        // Force getting a new shadowsocks relay instead of a cached one
                        skipShadowsocksCache = true
                    }
                    parallelRequestsMutex.unlock()
                }
                completion(data, response, maybeError)
            }

        return transport.sendRequest(request, completion: failureCompletionHandler)
    }

    private func makeTransport() -> RESTTransport? {
        if currentTransport == nil {
            switch transportStrategy.connectionTransport() {
            case .useShadowsocks:
                currentTransport = shadowsocksTransport()
            case .useURLSession:
                currentTransport = transport()
            }
        }
        return currentTransport
    }

    /// The last used shadowsocks configuration
    ///
    /// The last used shadowsocks configuration if any, otherwise a random one selected by `RelaySelector`
    /// - Returns: A shadowsocks configuration
    private func shadowsocksConfiguration() throws -> ShadowsocksConfiguration {
        // If a previous shadowsocks configuration was in cache, return it directly
        if skipShadowsocksCache == false, let configuration = shadowsocksCache.configuration {
            return configuration
        }
        // Reset the flag to avoid getting a new configuration until the current one becomes invalid
        skipShadowsocksCache = false

        // There is no previous configuration either if this is the first time this code ran
        // Or because the previous shadowsocks configuration was invalid, therefore generate a new one.
        let cachedRelays = try relayCache.read()
        let bridgeAddress = RelaySelector.getShadowsocksRelay(relays: cachedRelays.relays)?.ipv4AddrIn
        let bridgeConfiguration = RelaySelector.getShadowsocksTCPBridge(relays: cachedRelays.relays)

        guard let bridgeAddress, let bridgeConfiguration else { throw POSIXError(.ENOENT) }

        let newConfiguration = ShadowsocksConfiguration(
            bridgeAddress: bridgeAddress,
            bridgePort: bridgeConfiguration.port,
            password: bridgeConfiguration.password,
            cipher: bridgeConfiguration.cipher
        )
        shadowsocksCache.configuration = newConfiguration
        return newConfiguration
    }
}
