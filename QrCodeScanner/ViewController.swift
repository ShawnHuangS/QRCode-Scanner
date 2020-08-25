//
//  ViewController.swift
//  QrCodeScanner
//
//  Created by ShawnHuang on 2020/8/25.
//  Copyright © 2020 ShawnHuang. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    var qrCodeScanner : QrCodeScanner?
    
    
    @IBOutlet weak var cameraPresentView: UIView!
    @IBOutlet weak var retryBtn: UIButton! {
        didSet{
            retryBtn.isHidden = true
        }
    }
    @IBOutlet weak var scanLabel: UILabel! {
        didSet{
            scanLabel.text = ""
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

    }
    override func viewWillAppear(_ animated: Bool) {
        qrCodeScanner = QrCodeScanner(cameraPresentView: cameraPresentView , delegate: self)
    }
    override func viewWillDisappear(_ animated: Bool) {
        qrCodeScanner?.stopRunning()
        qrCodeScanner = nil
    }
    
    @IBAction func retryBtnPress(_ sender: Any) {
        
        guard let scanner = qrCodeScanner else {
            return
        }
        retryBtn.isHidden.toggle()
        scanLabel.text = ""
        scanner.startRunning()
    }
}
extension ViewController :  QrCodeDelegate
{
    func foundCode(code: String) {
        retryBtn.isHidden.toggle()
        scanLabel.text = code
        print("sacn : " + code)
    }
    
}

