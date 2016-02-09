//
//  BRAPIClient.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 11/4/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


import Foundation

let BRAPIClientErrorDomain = "BRApiClientErrorDomain"

public typealias URLSessionTaskHandler = (NSData?, NSHTTPURLResponse?, NSError?) -> Void
public typealias URLSessionChallengeHandler = (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void

extension String {
    static var urlQuoteCharacterSet: NSCharacterSet {
        let cset = NSMutableCharacterSet.URLQueryAllowedCharacterSet().mutableCopy() as! NSMutableCharacterSet
        cset.removeCharactersInString("?=&")
        return cset
    }
    
    var urlEscapedString: String {
        return self.stringByAddingPercentEncodingWithAllowedCharacters(
            String.urlQuoteCharacterSet)!
    }
}

func getHeaderValue(k: String, d: Dictionary<NSObject, AnyObject>) -> String? {
    if let v = d[k] as? String { // short path: attempt to get the header directly
        return v
    }
    let lkKey = k.lowercaseString // long path: compare lowercase keys
    for (lk, lv) in d {
        if lk is String {
            let lks = lk as! String
            if lks.lowercaseString == lkKey {
                if let lvs = lv as? String {
                    return lvs
                }
            }
        }
    }
    return nil
}

func getAuthKey() -> BRKey? {
    if let manager = BRWalletManager.sharedInstance(), authKey = manager.authPrivateKey {
        return BRKey(privateKey: authKey)
    }
    return nil
}

func getDeviceId() -> String {
    let ud = NSUserDefaults.standardUserDefaults()
    if let s = ud.stringForKey("BR_DEVICE_ID") {
        return s
    }
    let s = CFUUIDCreateString(nil, CFUUIDCreate(nil)) as String
    ud.setValue(s, forKey: "BR_DEVICE_ID")
    print("new device id \(s)")
    return s
}

func isBreadChallenge(r: NSHTTPURLResponse) -> Bool {
    if let challenge = getHeaderValue("www-authenticate", d: r.allHeaderFields) {
        if challenge.lowercaseString.hasPrefix("bread") {
            return true
        }
    }
    return false
}

func buildURLResourceString(url: NSURL?) -> String {
    var urlStr = ""
    if let url = url, path = url.path {
        urlStr = "\(path)"
        if let query = url.query {
            if query.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 0 {
                urlStr = "\(urlStr)?\(query)"
            }
        }
    }
    return urlStr
}

func buildRequestSigningString(r: NSMutableURLRequest) -> String {
    let headers = r.allHTTPHeaderFields ?? Dictionary<String, String>()
    var parts = [
        r.HTTPMethod,
        "",
        getHeaderValue("content-type", d: headers) ?? "",
        getHeaderValue("date", d: headers) ?? "",
        buildURLResourceString(r.URL)
    ]
    switch r.HTTPMethod {
    case "POST", "PUT", "PATCH":
        if let d = r.HTTPBody {
            let sha = d.SHA256()
            parts[1] = NSData(UInt256: sha).base58String()
        }
    default: break
    }
    return parts.joinWithSeparator("\n")
}

func buildResponseSigningString(req: NSMutableURLRequest, res: NSHTTPURLResponse, data: NSData? = nil) -> String {
    let parts: [String] = [
        req.HTTPMethod,
        "\(res.statusCode)",
        data != nil ? NSData(UInt256: data!.SHA256()).base58String() : "",
        getHeaderValue("content-type", d: res.allHeaderFields) ?? "",
        getHeaderValue("date", d: res.allHeaderFields) ?? "",
        buildURLResourceString(res.URL)
    ]
    
    return parts.joinWithSeparator("\n")
}

var rfc1123DateFormatter: NSDateFormatter {
    let fmt = NSDateFormatter()
    fmt.timeZone = NSTimeZone(abbreviation: "GMT")
    fmt.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'";
    fmt.locale = NSLocale(localeIdentifier: "en_US")
    return fmt
}

func httpDateNow() -> String {
    return rfc1123DateFormatter.stringFromDate(NSDate())
}

@objc public class BRAPIClient: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate {
    var logEnabled = true
    var proto = "https"
    var host = "api.breadwallet.com"
    
    private var _session: NSURLSession? = nil
    var session: NSURLSession {
        if _session == nil {
            let config = NSURLSessionConfiguration.defaultSessionConfiguration()
            _session = NSURLSession(configuration: config, delegate: self, delegateQueue: queue)
        }
        return _session!
    }
    var queue = NSOperationQueue()
    
    var baseUrl: String {
        return "\(proto)://\(host)"
    }
    
    var userAccountKey: String {
        return baseUrl
    }
    
    private var _serverPubKey: BRKey? = nil
    var serverPubKey: BRKey {
        if _serverPubKey == nil {
            let encoded = "24jsCR3itNGbbmYbZnG6jW8gjguhqybCXsoUAgfqdjprz"
            _serverPubKey = BRKey(publicKey: NSData(base58String: encoded))!
        }
        return _serverPubKey!
    }
    
    // the singleton
    static let sharedClient = BRAPIClient()
    
    
    func log(format: String, args: CVarArgType...) -> Int? {
        if !logEnabled {
            return 1
        }
        let s = String(format: format, arguments: args)
        print("[BRAPIClient] \(s)")
        return 2
    }
    
    // MARK: Networking functions
    
    // Constructs a full NSURL for a given path and url parameters
    func url(path: String, args: Dictionary<String, String>? =  nil) -> NSURL {
        func joinPath(k: String...) -> NSURL {
            return NSURL(string: ([baseUrl] + k).joinWithSeparator(""))!
        }
        
        if let args = args {
            return joinPath(path + "?" + args.map({ (elem) -> String in
                return "\(elem.0.urlEscapedString)=\(elem.1.urlEscapedString)"
            }).joinWithSeparator("&"))
        } else {
            return joinPath(path)
        }
    }
    
    func signRequest(request: NSURLRequest) -> NSURLRequest {
        let mutableRequest = request.mutableCopy() as! NSMutableURLRequest
        let dateHeader = getHeaderValue("date", d: mutableRequest.allHTTPHeaderFields ?? Dictionary<String, String>())
        if dateHeader == nil {
            // add Date header if necessary
            mutableRequest.setValue(httpDateNow(), forHTTPHeaderField: "Date")
        }
        do {
            if let tokenData = try BRKeychain.loadDataForUserAccount(userAccountKey),
                token = tokenData["token"], authKey = getAuthKey() {
                let sha = buildRequestSigningString(mutableRequest).dataUsingEncoding(NSUTF8StringEncoding)!.SHA256_2()
                let sig = authKey.compactSign(sha)!.base58String()
                mutableRequest.setValue("bread \(token):\(sig)", forHTTPHeaderField: "Authorization")
            }
        } catch let e as BRKeychainError {
            log("keychain error fetching tokoen \(e)")
        } catch let e {
            log("unexpected error fetching keychain data \(e)")
        }
        return mutableRequest.copy() as! NSURLRequest
    }
    
    func verifyResponse(request: NSMutableURLRequest, response: NSHTTPURLResponse, data: NSData?) -> Bool {
        // ensure the signature header is present and in the correct format
        guard let sigHeader = getHeaderValue("signature", d: response.allHeaderFields),
            sigRange = sigHeader.rangeOfString("bread ")
            where sigHeader.startIndex.distanceTo(sigRange.startIndex) == 0 else { return false }
        
        // extract signing signature bytes and signing string
        let sigStr = sigHeader[sigRange.endIndex..<sigHeader.endIndex],
            sig = NSData(base58String: sigStr),
            signingString = buildResponseSigningString(request, res: response, data: data)
        
        // extract the public key and ensure it equals the one we have configured
        if let sha = signingString.dataUsingEncoding(NSUTF8StringEncoding)?.SHA256_2(),
            pk = BRKey(recoveredFromCompactSig: sig, andMessageDigest: sha),
            pkDatA = pk.publicKey, pkDatB = serverPubKey.publicKey
            where pkDatA.isEqualToData(pkDatB) { return true }
        return false
    }
    
    func dataTaskWithRequest(request: NSURLRequest, authenticated: Bool = false, verify: Bool = true,
                             retryCount: Int = 0, handler: URLSessionTaskHandler) -> NSURLSessionDataTask {
        let start = NSDate()
        var logLine = ""
        if let meth = request.HTTPMethod, u = request.URL {
            logLine = "\(meth) \(u) auth=\(authenticated) retry=\(retryCount)"
        }
        let origRequest = request.mutableCopy() as! NSURLRequest
        var actualRequest = request
        if authenticated && getAuthKey() != nil {
            actualRequest = signRequest(request)
        }
        return session.dataTaskWithRequest(actualRequest) { (data, resp, err) -> Void in
            let end = NSDate()
            let dur = Int(end.timeIntervalSinceDate(start) * 1000)
            if let httpResp = resp as? NSHTTPURLResponse {
                var errStr = ""
                if httpResp.statusCode >= 400 {
                    if let data = data, s = NSString(data: data, encoding: NSUTF8StringEncoding) {
                        errStr = s as String
                    }
                }
                var verified = true
                if verify {
                    let mreq = actualRequest.mutableCopy() as! NSMutableURLRequest
                    verified = self.verifyResponse(mreq, response: httpResp, data: data)
                }
                
                self.log("\(logLine) -> status=\(httpResp.statusCode) duration=\(dur)ms " +
                         "verified=\(verified) errStr=\(errStr)")
                
                if !verified {
                    return handler(nil, nil, NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString("Unable to verify server identity", comment: "")]))
                }
                if authenticated && isBreadChallenge(httpResp) {
                    self.log("got authentication challenge from API - will attempt to get token")
                    self.getToken({ (err) -> Void in
                        if err != nil && retryCount < 1 { // retry once
                            self.log("error retrieving token: \(err) - will retry")
                            dispatch_after(1, dispatch_get_main_queue(), { () -> Void in
                                self.dataTaskWithRequest(
                                    origRequest, authenticated: authenticated,
                                    retryCount: retryCount + 1, handler: handler).resume()
                            })
                        } else if err != nil && retryCount > 0 { // fail if we already retried
                            self.log("error retrieving token: \(err) - will no longer retry")
                            handler(nil, nil, err)
                        } else if retryCount < 1 { // no error, so attempt the request again
                            self.log("retrieved token, so retrying the original request")
                            self.dataTaskWithRequest(
                                origRequest, authenticated: authenticated,
                                retryCount: retryCount + 1, handler: handler).resume()
                        } else {
                            self.log("retried token multiple times, will not retry again")
                            handler(data, httpResp, err)
                        }
                    })
                } else {
                    handler(data, httpResp, err)
                }
            } else {
                self.log("\(logLine) encountered connection error \(err)")
                handler(data, nil, err)
            }
        }
    }
    
    // retrieve a token and save it in the keychain data for this account
    func getToken(handler: (NSError?) -> Void) -> Void {
        if getAuthKey() == nil {
            return handler(NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Wallet not ready", comment: "")]))
        }
        let req = NSMutableURLRequest(URL: url("/token"))
        req.HTTPMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let reqJson = [
            "pubKey": getAuthKey()!.publicKey!.base58String(),
            "deviceID": getDeviceId()
        ]
        do {
            let dat = try NSJSONSerialization.dataWithJSONObject(reqJson, options: .PrettyPrinted)
            req.HTTPBody = dat
        } catch (let e) {
            log("JSON Serialization error \(e)")
            return handler(NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("JSON Serialization Error", comment: "")]))
        }
        let task = session.dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let httpResp = resp as? NSHTTPURLResponse {
                // unsuccessful response from the server
                if httpResp.statusCode != 200 {
                    if let data = data {
                        if let s = String(data: data, encoding: NSUTF8StringEncoding) {
                            self.log("Token error: \(s)")
                        }
                    }
                    return handler(NSError(domain: BRAPIClientErrorDomain, code: httpResp.statusCode, userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString("Unable to retrieve API token", comment: "")]))
                }
            }
            if let data = data {
                do {
                    let json = try NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments)
                    self.log("POST /token: \(json)")
                    if let topObj = json as? NSDictionary,
                        tok = topObj["token"] as? NSString,
                        uid = topObj["userID"] as? NSString {
                        // success! store it in the keychain
                        let kcData = ["token": tok, "userID": uid]
                        do {
                            try BRKeychain.saveData(kcData, forUserAccount: self.userAccountKey)
                        } catch let e {
                            self.log("Error saving token in keychain \(e)")
                            return handler(NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                                NSLocalizedDescriptionKey: NSLocalizedString("Unable to save API token", comment: "")]))
                        }
                    }
                } catch let e {
                    self.log("JSON Deserialization error \(e)")
                }
            }
            handler(err)
        }
        task.resume()
    }
    
    // MARK: URLSession Delegate
    
    public func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
        log("URLSession didBecomeInvalidWithError: \(error)")
    }
    
    public func URLSession(session: NSURLSession, task: NSURLSessionTask,
                           didReceiveChallenge: NSURLAuthenticationChallenge,
                           completionHandler: URLSessionChallengeHandler) {
            log("URLSession task \(task) didReceivechallenge \(didReceiveChallenge.protectionSpace)")
            
    }
    
    public func URLSession(session: NSURLSession, didReceiveChallenge: NSURLAuthenticationChallenge,
                           completionHandler: URLSessionChallengeHandler) {
        log("URLSession didReceiveChallenge \(didReceiveChallenge) \(didReceiveChallenge.protectionSpace)")
        // handle HTTPS authentication
        if didReceiveChallenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if (didReceiveChallenge.protectionSpace.host == host
                && didReceiveChallenge.protectionSpace.serverTrust != nil) {
                log("URLSession challenge accepted!")
                completionHandler(.UseCredential,
                    NSURLCredential(forTrust: didReceiveChallenge.protectionSpace.serverTrust!))
            } else {
                log("URLSession challenge rejected")
                completionHandler(.RejectProtectionSpace, nil)
            }
        }
    }
    
    // MARK: API Functions
    
    // Fetches the /v1/fee-per-kb endpoint
    public func feePerKb(handler: (feePerKb: uint_fast64_t, error: String?) -> Void) {
        let req = NSURLRequest(URL: url("/v1/fee-per-kb"))
        let task = self.dataTaskWithRequest(req) { (data, response, err) -> Void in
            var feePerKb: uint_fast64_t = 0
            var errStr: String? = nil
            if err == nil {
                do {
                    let parsedObject: AnyObject? = try NSJSONSerialization.JSONObjectWithData(
                        data!, options: NSJSONReadingOptions.AllowFragments)
                    if let top = parsedObject as? NSDictionary, n = top["fee_per_kb"] as? NSNumber {
                        feePerKb = n.unsignedLongLongValue
                    }
                } catch (let e) {
                    self.log("fee-per-kb: error parsing json \(e)")
                }
                if feePerKb == 0 {
                    errStr = "invalid json"
                }
            } else {
                self.log("fee-per-kb network error: \(err)")
                errStr = "bad network connection"
            }
            handler(feePerKb: feePerKb, error: errStr)
        }
        task.resume()
    }
    
    public func me() {
        let req = NSURLRequest(URL: url("/me"))
        let task = dataTaskWithRequest(req, authenticated: true) { (data, resp, err) -> Void in
            if let data = data {
                if let s = String(data: data, encoding: NSUTF8StringEncoding) {
                    self.log("GET /me: \(s)")
                }
            }
        }
        task.resume()
    }
    
    // MARK: Assets API
    
    public class func bundleURL(bundleName: String) -> NSURL {
        let fm = NSFileManager.defaultManager()
        let docsUrl = fm.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
        let bundleDirUrl = docsUrl.URLByAppendingPathComponent("bundles", isDirectory: true)
        let bundleUrl = bundleDirUrl.URLByAppendingPathComponent("\(bundleName)-extracted", isDirectory: true)
        return bundleUrl
    }
    
    public func updateBundle(bundleName: String, handler: (error: String?) -> Void) {
        // 1. check if we already have a bundle given the name
        // 2. if we already have it:
        //    2a. get the sha256 of the on-disk bundle
        //    2b. request the versions of the bundle from server
        //    2c. request the diff between what we have and the newest one, if ours is not already the newest
        //    2d. apply the diff and extract to the bundle folder
        // 3. otherwise:
        //    3a. download and extract the bundle
        
        // set up the environment
        let fm = NSFileManager.defaultManager()
        let docsUrl = fm.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
        let bundleDirUrl = docsUrl.URLByAppendingPathComponent("bundles", isDirectory: true)
        let bundleUrl = bundleDirUrl.URLByAppendingPathComponent("\(bundleName).tar")
        let bundleDirPath = bundleDirUrl.path!
        let bundlePath = bundleUrl.path!
        let bundleExtractedUrl = bundleDirUrl.URLByAppendingPathComponent("\(bundleName)-extracted")
        let bundleExtractedPath = bundleExtractedUrl.path!
        
        // determines if the bundle exists, but also creates the bundles/extracted directory if it doesn't exist
        func exists() throws -> Bool {
            var attrs = try? fm.attributesOfItemAtPath(bundleDirPath)
            if attrs == nil {
                try fm.createDirectoryAtPath(bundleDirPath, withIntermediateDirectories: true, attributes: nil)
                attrs = try fm.attributesOfItemAtPath(bundleDirPath)
            }
            var attrsExt = try? fm.attributesOfFileSystemForPath(bundleExtractedPath)
            if attrsExt == nil {
                try fm.createDirectoryAtPath(bundleExtractedPath, withIntermediateDirectories: true, attributes: nil)
                attrsExt = try fm.attributesOfItemAtPath(bundleExtractedPath)
            }
            return fm.fileExistsAtPath(bundlePath)
        }
        
        // extracts the bundle
        func extract() throws {
            try BRTar.createFilesAndDirectoriesAtPath(bundleExtractedPath, withTarPath: bundlePath)
        }
        
        guard let bundleExists = try? exists() else {
            return handler(error: NSLocalizedString("error determining if bundle exists", comment: "")) }
        
        if bundleExists {
            // bundle exists, download and apply the diff, then remove diff file
            log("bundle \(bundleName) exists, fetching diff for most recent version")
            
            guard let curBundleContents = NSData(contentsOfFile: bundlePath) else {
                return handler(error: NSLocalizedString("error reading current bundle", comment: "")) }
            
            let curBundleSha = NSData(UInt256: curBundleContents.SHA256())!.hexString
            
            dataTaskWithRequest(NSURLRequest(URL: url("/assets/bundles/\(bundleName)/versions")))
                { (data, resp, err) -> Void in
                    if let data = data,
                        parsed = try? NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments),
                        top = parsed as? NSDictionary,
                        versions = top["versions"] as? [String]
                        where err == nil {
                            if versions.indexOf(curBundleSha) == (versions.count - 1) { // have the most recent version
                                self.log("already at most recent version of bundle \(bundleName)")
                                do {
                                    try extract()
                                    return handler(error: nil)
                                } catch let e {
                                    return handler(error:
                                        NSLocalizedString("error extracting bundle: " + "\(e)", comment: ""))
                                }
                            } else { // don't have the most recent version, download diff
                                self.log("Fetching most recent version of bundle \(bundleName)")
                                let req = NSURLRequest(URL:
                                    self.url("/assets/bundles/\(bundleName)/diff/\(curBundleSha)"))
                                self.dataTaskWithRequest(req, handler: { (diffDat, diffResp, diffErr) -> Void in
                                    if let diffDat = diffDat,
                                        diffPath = bundleDirUrl.URLByAppendingPathComponent("\(bundleName).diff").path,
                                        oldBundlePath = bundleDirUrl.URLByAppendingPathComponent("\(bundleName).old").path
                                    where diffErr == nil {
                                        do {
                                            if fm.fileExistsAtPath(diffPath) {
                                                try fm.removeItemAtPath(diffPath)
                                            }
                                            if fm.fileExistsAtPath(oldBundlePath) {
                                                try fm.removeItemAtPath(oldBundlePath)
                                            }
                                            try diffDat.writeToFile(diffPath, options: .DataWritingAtomic)
                                            try fm.moveItemAtPath(bundlePath, toPath: oldBundlePath)
                                            try BRBSPatch.patch(
                                                oldBundlePath, newFilePath: bundlePath, patchFilePath: diffPath)
                                            try fm.removeItemAtPath(diffPath)
                                            try fm.removeItemAtPath(oldBundlePath)
                                            try extract()
                                            return handler(error: nil)
                                        } catch let e {
                                            // something failed, clean up whatever we can, next attempt will download fresh
                                            _ = try? fm.removeItemAtPath(diffPath)
                                            _ = try? fm.removeItemAtPath(oldBundlePath)
                                            _ = try? fm.removeItemAtPath(bundlePath)
                                            return handler(error:
                                                NSLocalizedString("error downloading diff: " + "\(e)", comment: ""))
                                        }
                                    }
                                }).resume()
                            }
                        }
                    else {
                        return handler(error: NSLocalizedString("error determining versions", comment: ""))
                    }
                }.resume()
        } else {
            // bundle doesn't exist. download a fresh copy
            log("bundle \(bundleName) doesn't exist, downloading new copy")
            let req = NSURLRequest(URL: url("/assets/bundles/\(bundleName)/download"))
            dataTaskWithRequest(req) { (data, response, err) -> Void in
                if err != nil {
                    return handler(error: NSLocalizedString("error fetching bundle: ", comment: "") + "\(err)")
                }
                if let data = data {
                    do {
                        try data.writeToFile(bundlePath, options: .DataWritingAtomic)
                        try extract()
                        return handler(error: nil)
                    } catch let e {
                        return handler(error: NSLocalizedString("error writing bundle file: ", comment: "") + "\(e)")
                    }
                }
            }.resume()
        }
    }
    
    public func serveBundle(bundleName: String, debugURL: String? = nil) -> BRHTTPServer? {
        let ret = BRHTTPServer(baseDirectory: BRAPIClient.bundleURL(bundleName))
        do {
            try ret.start()
            if debugURL != nil {
                ret.debugFrom(NSURL(string: debugURL!))
            }
            return ret
        } catch let e {
            log("Error starting http server: \(e)")
        }
        return nil
    }
}

extension NSData {
    var hexString : String {
        let buf = UnsafePointer<UInt8>(bytes)
        let charA = UInt8(UnicodeScalar("a").value)
        let char0 = UInt8(UnicodeScalar("0").value)
        
        func itoh(i: UInt8) -> UInt8 {
            return (i > 9) ? (charA + i - 10) : (char0 + i)
        }
        
        let p = UnsafeMutablePointer<UInt8>.alloc(length * 2)
        
        for i in 0..<length {
            p[i*2] = itoh((buf[i] >> 4) & 0xF)
            p[i*2+1] = itoh(buf[i] & 0xF)
        }
        
        return NSString(bytesNoCopy: p, length: length*2, encoding: NSUTF8StringEncoding, freeWhenDone: true) as! String
    }
}
