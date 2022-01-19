//
//  QrCodeScanner.swift
//
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
    private lazy var qrCodeFrameView : UIView = {
        let frameView = UIView()
		// change frameview color
        frameView.layer.borderColor = UIColor.green.cgColor
        frameView.layer.borderWidth = 3
        return frameView
    }()
    private lazy var scanView : UIView = {
        let scanView = UIView()
        scanView.layer.borderWidth = 3
        scanView.layer.borderColor = UIColor.red.cgColor
        cameraPresentView.addSubview(scanView)
        return scanView
    }()
    
    init(cameraPresentView : UIView , delegate : QrCodeDelegate) {
        super.init()
		
        NotificationCenter.default.addObserver(self, selector: #selector(videoOrientation),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
        self.delegate = delegate
        self.cameraPresentView = cameraPresentView
        setCamera()
        
    }
    deinit {
        print("\(self) deinit")
    }        
}
///private method
private extension QrCodeScanner {
    func setCamera(){
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
        let normal = CGFloat(20)
        let scanRect = CGRect(x: normal,
                              y: normal,
                              width: size.width - (normal * 2),
                              height: size.height - (normal * 2))
        
        scanView.frame = scanRect
        
        scanLineView.frame = CGRect(x: 5, y: 0, width: scanView.frame.width - 10, height: 2)
        scanLineView.backgroundColor = .green

        cameraPresentView.addSubview(qrCodeFrameView)
        cameraPresentView.bringSubviewToFront(qrCodeFrameView)
        
        scanView.addSubview(scanLineView)
        cameraPresentView.bringSubviewToFront(scanView)
        
        self.moveUpAndDownLine()
        metadataOutput.rectOfInterest = previewLayer.metadataOutputRectConverted(fromLayerRect: scanRect)
        startRunning()
                        
//        NotificationCenter.default.addObserver(forName: .AVCaptureInputPortFormatDescriptionDidChange , object: nil, queue: nil) { [weak self] (noti) in
//            guard let strongSelf = self else { return }
//            metadataOutput.rectOfInterest = strongSelf.previewLayer.metadataOutputRectConverted(fromLayerRect: scanRect)
//                }
        
    }
    
    func changeLayoutWith(state : LayoutState){
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
    
    func captureDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discoverySession.devices.first { $0.position == position }
    }
    
    func failed() {
        let ac = UIAlertController(title: "Scanning not supported",
                                   message: "Your device does not support scanning a code from an item. Please use a device with a camera.",
                                   preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
//        present(ac, animated: true)
        captureSession = nil
    }
    
    func moveUpAndDownLine() {
        let opts : UIView.AnimationOptions  = [.autoreverse , .repeat , .curveEaseInOut]
        
        UIView.animate(withDuration: scanSpeed , delay: 0, options: opts, animations: { [weak self] in
            guard let self = self else {return}
            self.scanLineView.frame.origin.y += self.scanView.frame.height - 2
            
        }) { [weak self] _ in
            guard let self = self else {return}
            self.scanLineView.frame.origin.y = 0
        }
    }
    
    @objc
    func videoOrientation() {
    if let connection = self.previewLayer.connection , connection.isVideoOrientationSupported {
        DispatchQueue.main.async {
            guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
                #if DEBUG
                fatalError("Could not obtain UIInterfaceOrientation from a valid windowScene")
                #else
                return nil
                #endif
            }
            if let videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue) {
                connection.videoOrientation = videoOrientation
            }
        }
    }
}
}
///public method
extension QrCodeScanner {
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
            if let barCodeObject = previewLayer.transformedMetadataObject(for: readableObject) {
                qrCodeFrameView.frame = barCodeObject.bounds
            }
        }
    }
    
    func found(code: String) {
        delegate?.foundCode(code: code)
    }
}
