//
//  FCMTokenRequest.swift
//  Beiwe
//
//  Created by Tucker Jaenicke on 5/11/20.
//  Copyright © 2020 Rocketfarm Studios. All rights reserved.
//

import Foundation
import ObjectMapper

struct FCMTokenRequest : Mappable, ApiRequest {
    
    static let apiEndpoint = "/set_fcm_token";
    typealias ApiReturnType = BodyResponse;
    
    var fcmToken: String?;
    
    init(fcmToken: String) {
        self.fcmToken = fcmToken;
    }
    
    init?(map: Map) {}
    
    // Mappable
    mutating func mapping(map: Map) {
        fcmToken <- map["fcm_token"];
    }
}
