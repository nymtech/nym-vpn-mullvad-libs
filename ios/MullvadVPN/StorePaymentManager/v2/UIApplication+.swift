//
//  UIApplication+.swift
//  MullvadVPN
//
//  Created by pronebird on 18/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import UIKit
import MullvadTypes

extension UIApplication {
    func withBackgroundTask<T>(
        name: String? = nil,
        cancelUponExpiration: Bool = true,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let task = Task { try await operation() }
        let backgroundTaskHandler = BackgroundTaskHandler(application: self)

        return try await withTaskCancellationHandler {
            backgroundTaskHandler.begin()
            defer { backgroundTaskHandler.end() }

            return try await task.value
        } onCancel: {
            if cancelUponExpiration {
                task.cancel()
            }

            backgroundTaskHandler.end()
        }
    }
}

private final class BackgroundTaskHandler {
    let application: BackgroundTaskProvider
    let name: String?
    private let stateLock = NSLock()

    private var taskId: UIBackgroundTaskIdentifier = .invalid

    init(application: BackgroundTaskProvider, name: String? = nil) {
        self.application = application
        self.name = name
    }

    func begin() {
        stateLock.withLock {
            guard taskId == .invalid else { return }

            taskId = application.beginBackgroundTask(withName: name, expirationHandler: { [weak self] in
                self?.end()
            })
        }
    }

    func end() {
        stateLock.withLock {
            guard taskId != .invalid else { return }

            application.endBackgroundTask(taskId)
            taskId = .invalid
        }
    }
}
