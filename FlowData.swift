//
//  FlowData.swift
//  BiteToByte
//
//  Created by Tabatha Guebard on 5/7/26.
//

import Foundation

struct FlowData: Codable, Identifiable {
    let id = UUID()
    let timestamp: String
    let rate: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case timestamp, rate, status
    }

    init(timestamp: String, rate: String, status: String) {
        self.timestamp = timestamp
        self.rate = rate
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        status    = try container.decode(String.self, forKey: .status)

        if let intRate = try? container.decode(Int.self, forKey: .rate) {
            rate = "\(intRate) mL/hr"
        } else {
            rate = try container.decode(String.self, forKey: .rate)
        }
    }
}
