//
//  UIApplication+.swift
//  MullvadVPN
//
//  Created by pronebird on 18/08/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import UIKit

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

            Task { await backgroundTaskHandler.end() }
        }
    }
}

private final class BackgroundTaskHandler {
    let application: UIApplication
    let name: String?

    private var taskId: UIBackgroundTaskIdentifier = .invalid

    init(application: UIApplication, name: String? = nil) {
        self.application = application
        self.name = name
    }

    @MainActor func begin(name: String? = nil) {
        guard taskId == .invalid else { return }

        taskId = application.beginBackgroundTask(withName: name, expirationHandler: { [weak self] in
            self?.end()
        })
    }

    @MainActor func end() {
        guard taskId != .invalid else { return }

        application.endBackgroundTask(taskId)
        taskId = .invalid
    }
}
