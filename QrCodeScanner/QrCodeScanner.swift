//
//  QrCodeScanner.swift
//  SmartAttendance
//
//  Created by ShawnHuang on 2020/6/29.
//  Copyright © 2020 ShawnHuang. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

protocol QrCodeDelegate : AnyObject{
    func foundCode(code : String)
}
class QrCodeScanner: NSObject {
    enum LayoutState {
        case init_layout
        case scanComplete
        case scanRetry
    }
    weak var delegate : QrCodeDelegate?
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let scanLineView = UIView()
    private let scanSpeed = TimeInterval(1)
    private var cameraPresentView : UIView!
    lazy var qrCodeFrameView : UIView = {
        let frameView = UIView()
        frameView.layer.borderColor = UIColor.green.cgColor
        frameView.layer.borderWidth = 5
        
        return frameView
    }()
    lazy var scanView : UIView = {
        let scanView = UIView()
        scanView.layer.borderWidth = 3
        scanView.layer.borderColor = UIColor.red.cgColor
        cameraPresentView.addSubview(scanView)
        return scanView
    }()
    
    init(cameraPresentView : UIView , delegate : QrCodeDelegate) {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(videoOrientation), name: UIApplication.didChangeStatusBarFrameNotification, object: nil)
        self.delegate = delegate
        self.cameraPresentView = cameraPresentView
        setCamera()
        
    }
    private func setCamera(){
        captureSession = AVCaptureSession()
        let position : AVCaptureDevice.Position = .back
        guard let videoCaptureDevice = self.captureDevice(forPosition: position) else { return }
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        if (captureSession!.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }
        let metadataOutput = AVCaptureMetadataOutput()
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            failed()
            return
        }
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = cameraPresentView.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        cameraPresentView.layer.addSublayer(previewLayer)
        self.videoOrientation()
        
        let size = cameraPresentView.frame.size
        let scanRect = CGRect(x: Int(size.width / 6),
                              y: Int(size.width / 6),
                              width: Int(size.width / 6) * 4,
                              height: Int(size.height / 6) * 4)
        let x = scanRect.origin.x / size.width
        let y = scanRect.origin.y / size.height
        let width = scanRect.width / size.width
        let height = scanRect.height / cameraPresentView.frame.height
        
        let scanRectTransformed = CGRect(x: x, y: y, width: width, height: height)
        metadataOutput.rectOfInterest = scanRectTransformed
        scanView.frame = scanRect
        

        scanLineView.frame = CGRect(x: 5, y: 0, width: scanView.frame.width - 10, height: 2)
        scanLineView.backgroundColor = .green
        
        cameraPresentView.addSubview(qrCodeFrameView)
        cameraPresentView.bringSubviewToFront(qrCodeFrameView)
        
        scanView.addSubview(scanLineView)
        cameraPresentView.bringSubviewToFront(scanView)
        
        self.moveUpAndDownLine()
        startRunning()
    }
    
    private func changeLayoutWith(state : LayoutState){
        switch state {
        case .init_layout:
            scanLineView.isHidden = false
            qrCodeFrameView.isHidden = true

        case .scanComplete:
            scanLineView.isHidden = true
            qrCodeFrameView.isHidden = false

        case .scanRetry:
            scanLineView.isHidden = true
            qrCodeFrameView.isHidden = false

        }
    }
    
    func startRunning(){
    if (captureSession?.isRunning == false) {
        captureSession.startRunning()
        changeLayoutWith(state: .init_layout)
    }
}
    func stopRunning(){
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
    }
    private func captureDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discoverySession.devices.first { $0.position == position }
    }
    private func failed() {
        let ac = UIAlertController(title: "Scanning not supported",
                                   message: "Your device does not support scanning a code from an item. Please use a device with a camera.",
                                   preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
//        present(ac, animated: true)
        captureSession = nil
    }
    private func moveUpAndDownLine() {
        let opts : UIView.AnimationOptions  = [.autoreverse , .repeat , .curveEaseInOut]
        
        UIView.animate(withDuration: scanSpeed , delay: 0, options: opts, animations: {
            self.scanLineView.frame.origin.y += self.scanView.frame.height - 2
        }) { (complete) in
            self.scanLineView.frame.origin.y = 0
        }
    }
    
    @objc
    private func videoOrientation() {
        if let connection = self.previewLayer.connection , connection.isVideoOrientationSupported {
            DispatchQueue.main.async {
                let orientation = UIApplication.shared.statusBarOrientation
                if let videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue) {
                    connection.videoOrientation = videoOrientation
                }
            }
        }
    }
    
}

extension QrCodeScanner : AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            //震動
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            
            changeLayoutWith(state: .scanComplete)
            found(code : stringValue)
            let barCodeObject = previewLayer.transformedMetadataObject(for: readableObject)
            qrCodeFrameView.frame = barCodeObject!.bounds
        }
    }
    
    func found(code: String) {
        delegate?.foundCode(code: code)
    }
}
