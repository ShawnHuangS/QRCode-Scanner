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
    private let metadataOutput = AVCaptureMetadataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var cameraPresentView : UIView!
    private let scanSpeed = TimeInterval(1)
    private lazy var scanLineView = { //  掃描線
        let scanLineV = UIView()
        scanLineV.frame = CGRect(x: 5, y: 0, width: scanView.frame.width - 10, height: 2)
        scanLineV.backgroundColor = .green
        return scanLineV
    }()
    
    private lazy var qrCodeFrameView : UIView = {   // 掃描到的qrcode框
        let frameView = UIView()
        // change frameview color
        frameView.layer.borderColor = UIColor.green.cgColor
        frameView.layer.borderWidth = 3
        return frameView
    }()
    private lazy var scanView : UIView = {
        let scanView = UIView()
//        scanView.layer.borderWidth = 3
//        scanView.layer.borderColor = UIColor.red.cgColor
        cameraPresentView.addSubview(scanView)
        return scanView
    }()  // 外框

    init(cameraPresentView : UIView , delegate : QrCodeDelegate) {
        super.init()
        
                        
        NotificationCenter.default.addObserver(self, selector: #selector(videoOrientation),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
        
        // 避免退到背景回到前景時掃描線停止  moveUpAndDownLine
        NotificationCenter.default.addObserver(self, selector: #selector(moveUpAndDownLine), name: .willEnterForeground, object: nil)
        
        self.delegate = delegate
        self.cameraPresentView = cameraPresentView
        setCamera()
    }
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .willEnterForeground , object: nil)
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
                
        let size = cameraPresentView.frame.size
        let normal =  size.width * 0.9 // CGFloat(20) // 內縮
        let scanRect = CGRect(x: normal,
                              y: normal,
                              width: size.width - (normal * 2),
                              height: size.height - (normal * 2))
//        scanView
        scanView.frame = scanRect
        
        let lineLength = 26.7
//        create path
        let path = UIBezierPath()
//        left-top
        path.move(to: CGPoint(x: 0, y: lineLength))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: lineLength, y: 0))
//        right-top
        path.move(to: CGPoint(x: scanView.frame.width - lineLength, y: 0))
        path.addLine(to: CGPoint(x: scanView.frame.width, y: 0))
        path.addLine(to: CGPoint(x: scanView.frame.width, y: lineLength))
//        right-bottom
        path.move(to: CGPoint(x: scanView.frame.width, y: scanView.frame.height - lineLength))
        path.addLine(to: CGPoint(x: scanView.frame.width, y: scanView.frame.height))
        path.addLine(to: CGPoint(x: scanView.frame.width - lineLength, y: scanView.frame.height))
//        left-bottom
        path.move(to: CGPoint(x: lineLength , y: scanView.frame.height))
        path.addLine(to: CGPoint(x: 0, y: scanView.frame.height))
        path.addLine(to: CGPoint(x: 0, y: scanView.frame.height - lineLength))

//        create shape layer
        let shapeLayer = CAShapeLayer()
        shapeLayer.strokeColor = UIColor.white.cgColor  // 線條顏色
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = 5
        shapeLayer.path = path.cgPath
        scanView.layer.addSublayer(shapeLayer)
        
        // create mask layer
        let maskView = UIView(frame: cameraPresentView.bounds)
        maskView.backgroundColor = .black.withAlphaComponent(0.6)
        let blackPath = UIBezierPath(rect: maskView.frame)
        let emptyPath = UIBezierPath(rect: scanView.frame).reversing()
        blackPath.append(emptyPath)
        let maskLayer = CAShapeLayer()
        maskLayer.path = blackPath.cgPath
        maskView.layer.mask = maskLayer
        cameraPresentView.addSubview(maskView)
        


        cameraPresentView.addSubview(qrCodeFrameView)
        cameraPresentView.bringSubviewToFront(qrCodeFrameView)
        
        scanView.addSubview(scanLineView)
        cameraPresentView.bringSubviewToFront(scanView)
        self.moveUpAndDownLine()

        startRunning()
//        metadataOutput.rectOfInterest = previewLayer.metadataOutputRectConverted(fromLayerRect: CGRect.zero)
        videoOrientation()

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
    
    @objc
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
            DispatchQueue.main.async { [self] in
                guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
                    #if DEBUG
                        fatalError("Could not obtain UIInterfaceOrientation from a valid windowScene")
                    #else
                        return
                    #endif
                }
                
                if let videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue) {
                    connection.videoOrientation = videoOrientation
                    metadataOutput.rectOfInterest = previewLayer.metadataOutputRectConverted(fromLayerRect: scanView.frame)
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


extension Notification.Name {
    static let willEnterForeground = UIApplication.willEnterForegroundNotification
}
