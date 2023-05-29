//
//  AccountRedeemVoucherController.swift
//  MullvadVPN
//
//  Created by pronebird on 28/09/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import MullvadREST
import UIKit

protocol AccountRedeemVoucherControllerDelegate: AnyObject {
    func redeemVoucherControllerDidFinish(_ controller: AccountRedeemVoucherController)
    func redeemVoucherControllerDidCancel(_ controller: AccountRedeemVoucherController)
}

class AccountRedeemVoucherController: UINavigationController, UINavigationControllerDelegate {
    override var presentedViewController: UIViewController {
        UIViewController()
    }

    weak var redeemVoucherDelegate: AccountRedeemVoucherControllerDelegate?
    private var customTransitioningDelegate = FormSheetTransitioningDelegate()

    init(interactor: RedeemVoucherInteractor) {
        super.init(nibName: nil, bundle: nil)
        delegate = self
        configureUI()
        setupContentView(interactor: interactor)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupContentView(interactor: RedeemVoucherInteractor) {
        let redeemVoucherViewController = RedeemVoucherViewController(interactor: interactor)
        redeemVoucherViewController.delegate = self
        pushViewController(redeemVoucherViewController, animated: false)
    }

    private func configureUI() {
        isNavigationBarHidden = true
        preferredContentSize = CGSize(width: 320, height: 290)
        modalPresentationStyle = .custom
        modalTransitionStyle = .crossDissolve
        transitioningDelegate = customTransitioningDelegate
    }
}

extension AccountRedeemVoucherController: RedeemVoucherViewControllerDelegate {
    func redeemVoucherInputViewController(
        _ controller: RedeemVoucherViewController,
        didRedeemVoucherWithResponse response: REST.SubmitVoucherResponse
    ) {
        let controller = RedeemVoucherSucceededViewController(
            timeAddedComponents: response.dateComponents
        )
        controller.delegate = self

        pushViewController(controller, animated: true)
    }

    func redeemVoucherInputViewControllerDidCancel(_ controller: RedeemVoucherViewController) {
        redeemVoucherDelegate?.redeemVoucherControllerDidCancel(self)
    }
}

extension AccountRedeemVoucherController: RedeemVoucherSucceededViewControllerDelegate {
    func redeemVoucherSucceededViewControllerDidFinish(
        _ controller: RedeemVoucherSucceededViewController
    ) {
        redeemVoucherDelegate?.redeemVoucherControllerDidFinish(self)
    }
}
