//
//  RedeemVoucherViewController.swift
//  MullvadVPN
//
//  Created by Andreas Lif on 2022-08-05.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import MullvadREST
import MullvadTypes
import UIKit

protocol RedeemVoucherViewControllerDelegate: AnyObject {
    func redeemVoucherInputViewController(
        _ controller: RedeemVoucherViewController,
        didRedeemVoucherWithResponse response: REST.SubmitVoucherResponse
    )
    func redeemVoucherInputViewControllerDidCancel(_ controller: RedeemVoucherViewController)
}

class RedeemVoucherViewController: UIViewController, UINavigationControllerDelegate {
    private let contentView = RedeemVoucherContentView()
    private var didBecomeFirstResponder = false
    private var voucherTask: Cancellable?
    private var interactor: RedeemVoucherInteractor?

    weak var delegate: RedeemVoucherViewControllerDelegate?
    init(interactor: RedeemVoucherInteractor) {
        super.init(nibName: nil, bundle: nil)
        self.interactor = interactor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    // MARK: - Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        addActions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resignVoucherTextField()
    }

    // MARK: - private functions

    private func resignVoucherTextField() {
        guard !didBecomeFirstResponder else { return }
        didBecomeFirstResponder = true
        contentView.textField.becomeFirstResponder()
    }

    private func addActions() {
        contentView.redeemAction = { [weak self] code in
            self?.submit(code: code)
        }

        contentView.cancelAction = { [weak self] in
            self?.cancel()
        }
    }

    private func configureUI() {
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func submit(code: String) {
        contentView.state = .verifying
        voucherTask = interactor?.redeem(code: code, completion: { [weak self] result in
            switch result {
            case let .success(value):
                self?.contentView.state = .success
                self?.notifyDelegateDidRedeemVoucher(value)
            case let .failure(error):
                self?.contentView.state = .failure(error)
            }
        })
    }

    private func notifyDelegateDidRedeemVoucher(_ response: REST.SubmitVoucherResponse) {
        delegate?.redeemVoucherInputViewController(self, didRedeemVoucherWithResponse: response)
    }

    private func cancel() {
        contentView.textField.resignFirstResponder()

        voucherTask?.cancel()

        delegate?.redeemVoucherInputViewControllerDidCancel(self)
    }
}
