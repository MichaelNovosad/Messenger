//
//  AllMessagesModel.swift
//  Messenger
//
//  Created by Michael Novosad on 27.08.2022.
//

import Foundation

public struct MessagesModel: Codable {
    public var name: String
    public var is_read: Bool
    public var id: String
    public var content: String
    public var sender_email: String
    public var date: String
    public var type: String
}
