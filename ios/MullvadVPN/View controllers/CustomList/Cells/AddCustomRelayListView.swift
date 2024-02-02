//
//  AddCustomRelayListView.swift
//  MullvadVPN
//
//  Created by Mojgan on 2024-01-25.
//  Copyright © 2024 Mullvad VPN AB. All rights reserved.
//

import UIKit

class AddCustomRelayListView: UIView, UIContentView {
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

    private lazy var nameTextfield: CustomTextField = {
        let textfield = CustomTextField()
        textfield.textColor = .primaryColor
        textfield.font = .systemFont(ofSize: 15, weight: .semibold)
        textfield.backgroundColor = .white
        textfield.placeholder = NSLocalizedString(
            "ADD_CUSTOM_RELAY_LIST_PLACEHOLDER_TEXT",
            tableName: "CustomList",
            value: "Enter name",
            comment: ""
        )
        textfield.addAction(UIAction(handler: { [weak self] action in
            guard let textfield = action.sender as? UITextField,
                  let text = textfield.text else {
                return
            }
            self?.saveButton.alpha = text.isEmpty ? 0.2 : 0.6
        }), for: .editingChanged)
        return textfield
    }()

    private let saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(resource: .iconTickSml), for: .normal)
        button.tintColor = .white
        button.alpha = 0.2
        return button
    }()

    private let messageContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .secondaryColor
        return view
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = UIColor(white: 1, alpha: 0.6)
        label.text = NSLocalizedString(
            "ADD_CUSTOM_RELAY_LIST_TIP_TEXT",
            tableName: "CustomList",
            value: "Lists must have unique names.",
            comment: ""
        )
        return label
    }()

    private let verticalDividerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondaryColor
        return view
    }()

    private let horizontalDividerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondaryColor
        return view
    }()

    init(configuration: AddCustomRelayListView.Configuration) {
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
        addConstrainedSubviews([
            horizontalDividerView,
            nameTextfield,
            verticalDividerView,
            saveButton,
            messageContainer,
        ]) {
            horizontalDividerView.pinEdgesToSuperview(.all().excluding(.bottom))
            horizontalDividerView.heightAnchor.constraint(equalToConstant: 1)

            nameTextfield.pinEdgesToSuperviewMargins(PinnableEdges([.top(.zero), .leading(.zero)]))

            saveButton.pinEdgesToSuperviewMargins(PinnableEdges([.trailing(.zero)]))
            saveButton.widthAnchor.constraint(equalToConstant: 24)
            saveButton.heightAnchor.constraint(equalTo: saveButton.widthAnchor, multiplier: 1)
            saveButton.centerYAnchor.constraint(equalTo: nameTextfield.centerYAnchor)
            saveButton.leadingAnchor.constraint(equalTo: verticalDividerView.trailingAnchor, constant: 21)

            verticalDividerView.topAnchor.constraint(equalTo: nameTextfield.topAnchor, constant: 5)
            verticalDividerView.bottomAnchor.constraint(equalTo: nameTextfield.bottomAnchor, constant: -5)
            verticalDividerView.leadingAnchor.constraint(equalTo: nameTextfield.trailingAnchor, constant: 21)
            verticalDividerView.widthAnchor.constraint(equalToConstant: 1)

            messageContainer.pinEdgesToSuperview(.all().excluding(.top))
            messageContainer.topAnchor.constraint(equalTo: nameTextfield.bottomAnchor, constant: 6)
        }

        messageContainer.addConstrainedSubviews([messageLabel]) {
            messageLabel.pinEdgesToSuperviewMargins()
        }
    }

    private func apply(configuration: Configuration) {
        saveButton.addAction(configuration.primaryAction, for: .touchUpInside)
    }

    private func applyAppearance() {
        backgroundColor = .primaryColor.withAlphaComponent(0.6)
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 25)
        messageContainer.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 6,
            leading: 22,
            bottom: 20,
            trailing: 22
        )
    }
}

extension AddCustomRelayListView {
    struct Configuration: UIContentConfiguration, Equatable {
        /// Primary action for button.
        var primaryAction: UIAction

        func makeContentView() -> UIView & UIContentView {
            AddCustomRelayListView(configuration: self)
        }

        func updated(for state: UIConfigurationState) -> AddCustomRelayListView.Configuration {
            self
        }
    }
}
