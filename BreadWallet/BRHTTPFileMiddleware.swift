//
//  BRHTTPFileMiddleware.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/8/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation


@objc public class BRHTTPFileMiddleware: NSObject, BRHTTPMiddleware {
    var baseURL: NSURL!
    var debugURL: NSURL?
    
    init(baseURL: NSURL, debugURL: NSURL? = nil) {
        super.init()
        self.baseURL = baseURL
        self.debugURL = debugURL
    }
    
    public func handle(request: BRHTTPRequest, next: (BRHTTPMiddlewareResponse) -> Void) {
        var fileURL: NSURL!
        var body: NSData!
        var contentTypeHint: String? = nil
        if debugURL == nil {
            // fetch the file locally
            fileURL = baseURL.URLByAppendingPathComponent(request.path)
            guard let bb = NSData(contentsOfURL: fileURL) else {
                return next(BRHTTPMiddlewareResponse(request: request, response: nil))
            }
            body = bb
        } else {
            // download the file from the debug endpoint
            fileURL = debugURL!.URLByAppendingPathComponent(request.path)
            let req = NSURLRequest(URL: fileURL)
            let grp = dispatch_group_create()
            dispatch_group_enter(grp)
            NSURLSession.sharedSession().dataTaskWithRequest(req, completionHandler: { (dat, resp, err) -> Void in
                defer {
                    dispatch_group_leave(grp)
                }
                if err != nil {
                    return
                }
                if let dat = dat, resp = resp as? NSHTTPURLResponse {
                    body = dat
                    contentTypeHint = resp.allHeaderFields["content-type"] as? String
                } else {
                    
                }
            }).resume()
            dispatch_group_wait(grp, dispatch_time(DISPATCH_TIME_NOW, Int64(30) * Int64(NSEC_PER_SEC)))
            if body == nil {
                return next(BRHTTPMiddlewareResponse(request: request, response: nil))
            }
        }
        
        do {
            let privReq = request as! BRHTTPRequestImpl
            let rangeHeader = try privReq.rangeHeader()
            if rangeHeader != nil {
                let (end, start) = rangeHeader!
                let length = end - start
                let range = NSRange(location: start, length: length + 1)
                guard range.location + range.length <= body.length else {
                    let r =  BRHTTPResponse(
                        request: request, statusCode: 418, statusReason: "Request Range Not Satisfiable",
                        headers: nil, body: nil)
                    return next(BRHTTPMiddlewareResponse(request: request, response: r))
                }
                let subDat = body.subdataWithRange(range)
                let headers = [
                    "Content-Range": ["bytes \(start)-\(end)/\(body.length)"],
                    "Content-Type": [detectContentType(URL: fileURL)]
                ]
                var ary = [UInt8](count: subDat.length, repeatedValue: 0)
                subDat.getBytes(&ary, length: subDat.length)
                let r =  BRHTTPResponse(
                    request: request, statusCode: 200, statusReason: "OK", headers: headers, body: ary)
                return next(BRHTTPMiddlewareResponse(request: request, response: r))
            }
        } catch {
            let r = BRHTTPResponse(
                request: request, statusCode: 400, statusReason: "Bad Request", headers: nil,
                body: [UInt8]("Invalid Range Header".utf8))
            return next(BRHTTPMiddlewareResponse(request: request, response: r))
        }
        
        var ary = [UInt8](count: body.length, repeatedValue: 0)
        body.getBytes(&ary, length: body.length)
        let r = BRHTTPResponse(
            request: request,
            statusCode: 200,
            statusReason: "OK",
            headers: ["Content-Type": [contentTypeHint ?? detectContentType(URL: fileURL)]],
            body: ary)
        return next(BRHTTPMiddlewareResponse(request: request, response: r))
    }
    
    private func detectContentType(URL url: NSURL) -> String {
        if let ext = url.pathExtension {
            switch ext {
            case "ttf":
                return "application/font-truetype"
            case "woff":
                return "application/font-woff"
            case "otf":
                return "application/font-opentype"
            case "svg":
                return "image/svg+xml"
            case "html":
                return "text/html"
            case "png":
                return "image/png"
            case "jpeg", "jpg":
                return "image/jpeg"
            case "css":
                return "text/css"
            case "js":
                return "application/javascript"
            case "json":
                return "application/json"
            default: break
            }
        }
        return "application/octet-stream"
    }
}
