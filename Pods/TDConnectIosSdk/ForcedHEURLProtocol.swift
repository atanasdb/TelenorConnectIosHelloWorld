import UIKit

class ForcedHEURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        let shouldSkipInterceptionLogic
            = !(isWifiEnabled() && isCellularEnabled());
        if (shouldSkipInterceptionLogic) {
            // Better continue as iOS will block loading http in an https context
            //return false;
        }
        if (shouldFetchThroughCellular(request.url?.absoluteString)) {
            return true
        }
        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        let dict = openUrlThroughCellular(request.url?.absoluteString)
        if dict!["responseCode"] != nil {
            let contentType = String(describing: dict!["contentType"]!)
            let data = dict!["data"] as! NSData
            let response = URLResponse(url: self.request.url!, mimeType: contentType, expectedContentLength: data.length, textEncodingName: "")
            self.client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client!.urlProtocol(self, didLoad: data as Data)
            self.client!.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        print("Stop loading request URL = \(String(describing: request.url?.absoluteString))")
    }
}
