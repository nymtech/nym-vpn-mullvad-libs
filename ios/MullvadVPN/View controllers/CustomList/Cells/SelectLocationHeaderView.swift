//
//  SelectLocationHeaderView.swift
//  MullvadVPN
//
//  Created by Mojgan on 2024-01-25.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import Foundation
import UIKit

class SelectLocationHeaderView: UIView, UIContentView {
    var configuration: UIContentConfiguration {
        get {
            actualConfiguration
        } set {
            guard let newConfiguration = newValue as? Configuration,
                  actualConfiguration != newConfiguration else { return }
            let previousConfiguration = actualConfiguration
            actualConfiguration = newConfiguration
            apply(configuration: previousConfiguration)
        }
    }

    private var actualConfiguration: Configuration
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.textColor = .primaryTextColor
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        return label
    }()

    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(.add, for: .normal)
        button.tintColor = UIColor(white: 1, alpha: 0.6)
        return button
    }()

    private let dividerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondaryColor
        return view
    }()

    init(configuration: SelectLocationHeaderView.Configuration) {
        self.actualConfiguration = configuration
        super.init(frame: .zero)
        applyAppearance()
        addSubviews()
        apply(configuration: configuration)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addSubviews() {
        addConstrainedSubviews([nameLabel, dividerView, actionButton]) {
            nameLabel.pinEdgesToSuperviewMargins(.all().excluding(.trailing))
            actionButton.pinEdgesToSuperviewMargins(PinnableEdges([.trailing(.zero)]))
            actionButton.widthAnchor.constraint(equalToConstant: 24)
            actionButton.heightAnchor.constraint(equalTo: actionButton.widthAnchor, multiplier: 1)
            actionButton.centerYAnchor.constraint(equalTo: self.centerYAnchor)
            actionButton.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor, constant: 21)
            dividerView.pinEdgesToSuperview(PinnableEdges([.top(10), .bottom(10)]))
            dividerView.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 21)
            dividerView.widthAnchor.constraint(equalToConstant: 1)
        }
    }

    private func apply(configuration: Configuration) {
        let isActionHidden = (configuration.primaryAction == nil)
        nameLabel.text = configuration.name
        dividerView.isHidden = isActionHidden
        actionButton.isHidden = isActionHidden
        actualConfiguration.primaryAction.flatMap { [weak self] action in
            self?.actionButton.addAction(action, for: .touchUpInside)
        }
    }

    private func applyAppearance() {
        backgroundColor = .primaryColor
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 11, leading: 23, bottom: 11, trailing: 25)
    }
}

extension SelectLocationHeaderView {
    struct Configuration: UIContentConfiguration, Equatable {
        /// The text label.
        let name: String

        /// Primary action for button.
        var primaryAction: UIAction?

        func makeContentView() -> UIView & UIContentView {
            SelectLocationHeaderView(configuration: self)
        }

        func updated(for state: UIConfigurationState) -> SelectLocationHeaderView.Configuration {
            self
        }
    }
}
