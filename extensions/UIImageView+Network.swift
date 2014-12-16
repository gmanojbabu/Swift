//
//  UIImageView+Network.swift
//  Vooza
//
//  Created by GMB on 12/12/14.
//  Copyright (c) 2014 GMB. All rights reserved.
//

import Foundation
import UIKit
import ObjectiveC

@objc protocol GMBImageDownloadResponseDelegate {
    func imageDownloadResponse(response: NSURLResponse, didDownloadImage image: UIImage);
    func imageDownloadResponse(response: NSURLResponse?, didFaileWithError error:NSError);
}

typealias SuccessClosure = (response: NSURLResponse, image: UIImage) -> Void;
typealias FailureClosure = (response: NSURLResponse, error: NSError) -> Void;

class GMBImageDownloadOperation: NSOperation, NSURLConnectionDataDelegate {
    
    private var connection : NSURLConnection?
    private lazy var data: NSMutableData = NSMutableData()
    private var successCallBack: SuccessClosure?
    private var failureCallBack: FailureClosure?
    private var response: NSURLResponse? = nil
    
// MARK: - NSOperation life cycle
    
    var isOperationExecuting: Bool = false, isOperationFinished: Bool = false
    
    var isConcurrent : Bool {
        get {
            return true;
        }
    }
    
    var isExecuting: Bool {
        get {
            return isOperationExecuting;
        }
    }
    
    var isFinished: Bool {
        get {
            return isOperationFinished;
        }
    }
    
    init(imageURLRequest: NSURLRequest) {
        super.init()
        self.connection = NSURLConnection(request: imageURLRequest, delegate: self, startImmediately: false)
        self.connection?.setDelegateQueue(UIImageView.sharedOperationQueue)
    }
    
    func setSuccessBlock(onSuccessBlock: SuccessClosure, onFailureBlock: FailureClosure) {
        self.successCallBack = onSuccessBlock;
        self.failureCallBack = onFailureBlock;
    }
    
    override func start() {
        self.willChangeValueForKey("isExecuting")
        self.isOperationExecuting = true;
        self.didChangeValueForKey("isExecuting")
        self.connection?.start()
    }
    
    override func cancel() {
        finish();
        super.cancel();
    }
    
    func finish() {
        self.connection?.cancel();
        self.connection = nil;
        self.willChangeValueForKey("isExecuting")
        self.isOperationExecuting = false;
        self.didChangeValueForKey("isExecuting")
        
        self.willChangeValueForKey("isFinished")
        self.isOperationFinished = true;
        self.didChangeValueForKey("isFinished")
    }
    
// MARK: - NSURLConnectionDataDelegate
    
    func connection(connection: NSURLConnection, didReceiveResponse response: NSURLResponse) {
        self.response = response;
    }
    
    func connection(connection: NSURLConnection, didReceiveData data: NSData) {
        self.data.appendData(data);
    }
    
    func connectionDidFinishLoading(connection: NSURLConnection) {
        self.successCallBack?(response: self.response!, image: UIImage(data: self.data)!);
        finish();
    }
    
// MARK: - NSURLConnectionDelegate
    
    func connection(connection: NSURLConnection, didFailWithError error: NSError) {
        self.failureCallBack?(response: self.response!, error: error);
        finish();
    }
}

var AssociatedObjectHandle: UInt8 = 0

struct StaticImageNetworkStruct {
    static var operationQueue : NSOperationQueue? = nil
    static var onceTokenOpeationQueue: dispatch_once_t = 0
    static var imageCache : GMBImageCache? = nil
    static var onceTokenImageCache: dispatch_once_t = 0
}

extension UIImageView {
    
    class var sharedOperationQueue: NSOperationQueue {
        get {
            dispatch_once(&StaticImageNetworkStruct.onceTokenOpeationQueue, {
                StaticImageNetworkStruct.operationQueue = NSOperationQueue()
                StaticImageNetworkStruct.operationQueue?.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount
            })
            return StaticImageNetworkStruct.operationQueue!
        }
    }
    
    class var sharedImageCache: GMBImageCache {
        get {
            dispatch_once(&StaticImageNetworkStruct.onceTokenImageCache, {
                StaticImageNetworkStruct.imageCache = GMBImageCache()
                NSNotificationCenter.defaultCenter().addObserverForName(UIApplicationDidReceiveMemoryWarningNotification, object: nil, queue: NSOperationQueue.mainQueue(), usingBlock: { (notification) -> Void in
                    self.sharedImageCache.removeAllObjects()
                })
            })
            return StaticImageNetworkStruct.imageCache!
        }
    }
    
    private var gmb_imageDownloadOperation: GMBImageDownloadOperation? {
        get {
            return objc_getAssociatedObject(self, &AssociatedObjectHandle) as? GMBImageDownloadOperation;
        }
        
        set {
            objc_setAssociatedObject(self, &AssociatedObjectHandle, newValue, objc_AssociationPolicy(OBJC_ASSOCIATION_RETAIN_NONATOMIC))
        }
    }
    
    public func setImageWithURLRequest(request: NSURLRequest) {
        self.gmb_imageDownloadOperation?.cancel()
        
        var cachedImage: UIImage? = UIImageView.sharedImageCache.cachedImageForRequest(request)
        
        if cachedImage != nil {
            self.image = cachedImage;
        } else {
            self.image = nil;
            self.gmb_imageDownloadOperation = GMBImageDownloadOperation(imageURLRequest: request)
            self.gmb_imageDownloadOperation?.setSuccessBlock({[unowned self] (response: NSURLResponse, image: UIImage) -> Void in
                self.image = image;
                self.gmb_imageDownloadOperation = nil;
                UIImageView.sharedImageCache.cacheImage(image, forRequest: request)
                }, onFailureBlock: { [unowned self] (response: NSURLResponse, error: NSError) -> Void in
                    self.gmb_imageDownloadOperation = nil;
            })
            
            UIImageView.sharedOperationQueue.addOperation(self.gmb_imageDownloadOperation!)
        }
    }
}

class GMBImageCache: NSCache {
    
    func cachedImageForRequest(request: NSURLRequest) -> UIImage? {
        switch request.cachePolicy {
        case .ReloadIgnoringLocalCacheData, .ReloadIgnoringLocalAndRemoteCacheData:
            return nil;
        default:
            break;
        }
        return self.objectForKey(request.URL.absoluteString!) as? UIImage
    }
    
    func cacheImage(image: UIImage?, forRequest request: NSURLRequest?) {
        if (image != nil && request != nil) {
            self.setObject(image!, forKey: request!.URL.absoluteString!)
        }
    }
}