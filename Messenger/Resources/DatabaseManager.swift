//
//  DatabaseManager.swift
//  Messenger
//
//  Created by Michael Novosad on 07.08.2022.
//

import Foundation
import FirebaseDatabase
import MessageKit
import CoreLocation

/// Manager object to read and write data to real time firebase database
final class DatabaseManager {
    
    /// Shared instance of class
    public static let shared = DatabaseManager()
    
    private let database = Database.database().reference()
    
    private init() { }
    
    static func safeEmail(emailAddress: String) -> String {
        var safeEmail = emailAddress.replacingOccurrences(of: ".", with: "-")
        safeEmail = safeEmail.replacingOccurrences(of: "@", with: "-")
        return safeEmail
    }
}

extension DatabaseManager {
    /// Returns dictionary node at child path
    public func getDataFor(path: String, completion: @escaping (Result<Any, Error>) -> Void) {
        database.child("\(path)").observeSingleEvent(of: .value) { snapshot in
            guard let value = snapshot.value else { completion(.failure(DatabaseError.failedToFetch)); return }
            completion(.success(value))
        }
    }
}

extension DatabaseManager {
    public func returnSafeUserEmail() -> String {
        guard let currentEmail = UserDefaults.standard.value(forKey: "email") as? String else { return "" }
        return DatabaseManager.safeEmail(emailAddress: currentEmail)
    }
    
    public func returnUserName() -> String {
        guard let currentName = UserDefaults.standard.value(forKey: "name") as? String else { return "" }
        return currentName
    }
}

// MARK: - Account management

extension DatabaseManager {
    
    /// Checks if user exists for given email
    /// Parameters
    ///  - `email`:               Target email to be checked
    ///  - `completion`:    Async closure to return with result
    public func userExists(with email: String,
                           completion: @escaping ((Bool) -> Void)) {
        
        let safeEmail = DatabaseManager.safeEmail(emailAddress: email)
        database.child(safeEmail).observeSingleEvent(of: .value) { snapshot in
            guard snapshot.value as? [String: Any] != nil else {
                completion(false)
                return
            }
            completion(true)
        }
    }
    
    /// Inserts new user to database
    public func insertUser(with user: ChatAppUser, completion: @escaping (Bool) -> Void) {
        database.child(user.safeEmail).setValue([
            "first_name": user.firstName,
            "last_name": user.lastName
        ]) { [weak self] error, _ in
            guard error == nil else {
                print("Failed to write to database")
                completion(false)
                return
            }
            let newElement = [
                "name": user.firstName + " " + user.lastName,
                "email": user.safeEmail
            ]
            self?.database.child("users").observeSingleEvent(of: .value) { [weak self] snapshot in
                if var usersCollection = snapshot.value as? [[String: String]] {
                    usersCollection.append(newElement)
                    
                    self?.database.child("users").setValue(usersCollection) { error, _ in
                        guard error == nil else { completion(false); return }
                        completion(true)
                    }
                }
                else {
                    self?.database.child("users").setValue(newElement) { error, _ in
                        guard error == nil else { completion(false); return }
                        completion(true)
                    }
                }
            }
            completion(true)
        }
    }
    
    /// Gets all users from database
    public func getAllUsers(completion: @escaping (Result<[[String: String]], Error>) -> Void) {
        database.child("users").observeSingleEvent(of: .value) { snapshot in
            guard let value = snapshot.value as? [[String: String]] else {
                completion(.failure(DatabaseError.failedToFetch))
                return
            }
            completion(.success(value))
        }
    }
    
    public enum DatabaseError: Error {
        case failedToFetch
        public var localisedDescription: String {
            switch self {
            case .failedToFetch:
                return "Could not fetch data"
            }
        }
    }
}

// MARK: - Sending messages / conversations
extension DatabaseManager {
    /// Creates a new conversation with target user email and first message sent
    public func createNewConversation(with otherUserEmail: String, name: String, firstMessage: Message, completion: @escaping (Bool) -> Void) {
        let safeEmail = self.returnSafeUserEmail()
        let ref = database.child("\(safeEmail)")
        database.child("\(safeEmail)").observeSingleEvent(of: .value) { [weak self] snapshot in
            guard var userNode = snapshot.value as? [String: Any] else {
                completion(false)
                print("User not found!")
                return
            }
            
            let messageDate = firstMessage.sentDate
            let dateString = ChatViewController.dateFormatter.string(from: messageDate)
            let conversationId = "conversation_\(firstMessage.messageId)"
            var message = ""
            
            switch firstMessage.kind {
            case .text(let messageText):
                message = messageText
            default:
                break
            }
            
            guard let newConversationData = self?.returnNewConversationData(
                conversationId: conversationId,
                otherUserEmail: otherUserEmail,
                name: name,
                date: dateString,
                message: message),
            let recipient_newConversationData = self?.returnRecipientConversationData(
                conversationId: conversationId,
                safeEmail: safeEmail,
                name: name,
                date: dateString,
                message: message)
            else { completion(false); return }
            
            self?.database.child("\(otherUserEmail)/conversations").observeSingleEvent(of: .value) { [weak self] snapshot in
                if var conversations = snapshot.value as? [[String: Any]] {
                    conversations.append(recipient_newConversationData)
                    self?.database.child("\(otherUserEmail)/conversations").setValue(conversations)
                } else {
                    self?.database.child("\(otherUserEmail)/conversations").setValue([recipient_newConversationData])
                }
            }
            
            if var conversations = userNode["conversations"] as? [[String: Any]] {
                conversations.append(newConversationData)
                userNode["conversations"] = conversations
                ref.setValue(userNode) { [weak self] error, _ in
                    guard error == nil else { completion(false); return }
                    
                    self?.finishCreatingConversation(conversationId: conversationId,
                                                     name: name,
                                                     firstMessage: firstMessage,
                                                     completion: completion)
                }
            } else {
                userNode["conversations"] = [ newConversationData ]
                ref.setValue(userNode) { [weak self] error, _ in
                    guard error == nil else { completion(false); return }
                    
                    self?.finishCreatingConversation(conversationId: conversationId,
                                                     name: name,
                                                     firstMessage: firstMessage,
                                                     completion: completion)
                }
            }
        }
    }
    
    private func returnNewConversationData(conversationId: String, otherUserEmail: String, name: String, date: String, message: String) -> [String: Any] {
        return [
            "id": conversationId,
            "other_user_email": otherUserEmail,
            "name": name,
            "latest_message": [
                "date": date,
                "message": message,
                "is_read": false
            ]
        ]
    }
    
    private func returnRecipientConversationData(conversationId: String, safeEmail: String, name: String, date: String, message: String) -> [String: Any] {
        return [
            "id": conversationId,
            "other_user_email": safeEmail,
            "name": name,
            "latest_message": [
                "date": date,
                "message": message,
                "is_read": false
            ]
        ]
    }
    
    private func finishCreatingConversation(conversationId: String, name: String, firstMessage: Message, completion: @escaping (Bool) -> Void) {
        let messageDate = firstMessage.sentDate
        let dateString = ChatViewController.dateFormatter.string(from: messageDate)
                
        let currentUserEmail = returnSafeUserEmail()
        var message = ""
        
        switch firstMessage.kind {
        case .text(let messageText):
            message = messageText
        default:
            break
        }
        
        let collectionMessage = returnMessageCollection(
            id: firstMessage.messageId,
            type: firstMessage.kind.messageKindString,
            message: message,
            date: dateString,
            currentUserEmail: currentUserEmail,
            name: name)
        
        let value: [String: Any] = [
            "messages": [ collectionMessage ]
        ]
        
        database.child("\(conversationId)").setValue(value) { error, _ in
            guard error == nil else { completion(false); return }
            completion(true)
        }
    }
    
    private func returnMessageCollection(id: String, type: String, message: String, date: String, currentUserEmail: String, name: String) -> [String: Any] {
        return [
            "id": id,
            "type": type,
            "content": message,
            "date": date,
            "sender_email": currentUserEmail,
            "is_read": false,
            "name": name
        ]
    }
    
    /// Fetches and returns all conversations for the user with passed in email
    public func getAllConversations(for email: String, completion: @escaping (Result<[Conversation], Error>) -> Void) {
        database.child("\(email)/conversations").observe(.value) { snapshot in
            guard let value = snapshot.value as? [[String: Any]] else {
                completion(.failure(DatabaseError.failedToFetch))
                return
            }
            
            let conversations: [Conversation] = value.compactMap { dictionary in
                guard let conversationId = dictionary["id"] as? String,
                      let name = dictionary["name"] as? String,
                      let otherUserEmail = dictionary["other_user_email"] as? String,
                      let latestMessage = dictionary["latest_message"] as? [String: Any],
                      let date = latestMessage["date"] as? String,
                      let message = latestMessage["message"] as? String,
                      let isRead = latestMessage["is_read"] as? Bool else {
                    return nil
                }
                let latestMessageObject = LatestMessage(date: date,
                                                        text: message,
                                                        isRead: isRead)
                return Conversation(id: conversationId,
                                    name: name,
                                    otherUserEmail: otherUserEmail,
                                    latestMessage: latestMessageObject)
                
            }
            completion(.success(conversations))
        }
    }
    
    /// Gets all messages for a given conversation
    public func getAllMessagesForConversation(with id: String, completion: @escaping (Result<[Message], Error>) -> Void) {
        database.child("\(id)/messages").observe(.value) { [weak self] snapshot in
            guard let value = snapshot.value as? [[String: Any]] else {
                completion(.failure(DatabaseError.failedToFetch))
                return
            }
            
            let messages: [Message] = value.compactMap { dictionary in
                guard let name = dictionary["name"] as? String,
                      let messageId = dictionary["id"] as? String,
                      let content = dictionary["content"] as? String,
                      let senderEmail = dictionary["sender_email"] as? String,
                      let dateString = dictionary["date"] as? String,
                      let type = dictionary["type"] as? String,
                      let date = ChatViewController.dateFormatter.date(from: dateString)
                else { return nil }
                
                var kind: MessageKind?
                if type == "video" {
                    guard let video = self?.returnVideoData(content) else { return nil }
                    kind = .video(video)
                } else if type == "photo" {
                    guard let photo = self?.returnPhotoData(content) else { return nil }
                    kind = .photo(photo)
                } else if type == "location" {
                    guard let location = self?.returnLocationData(content) else { return nil }
                    kind = .location(location)
                } else {
                    kind = .text(content)
                }
                
                guard let finalKind = kind else { return nil }
                
                let sender = Sender(photoURL: "",
                                    senderId: senderEmail,
                                    displayName: name)
                return Message(sender: sender, messageId: messageId, sentDate: date, kind: finalKind)
            }
            completion(.success(messages))
        }
    }
    
    /// Returns photo data for getAllMessages method according to its content.
    private func returnPhotoData(_ content: String) -> Media? {
        guard let imageUrl = URL(string: content),
              let placeholder = UIImage(systemName: "plus")
        else { return nil}
        
        let media = Media(url: imageUrl,
                          image: nil,
                          placeholderImage: placeholder,
                          size: CGSize(width: 300, height: 300))
        return media
    }
    
    /// Returns video data for getAllMessages method according to its content.
    private func returnVideoData(_ content: String) -> Media? {
        guard let videoUrl = URL(string: content),
              let placeholder = UIImage(named: "video_placeholder")
        else { return nil}
        
        let media = Media(url: videoUrl,
                          image: nil,
                          placeholderImage: placeholder,
                          size: CGSize(width: 300, height: 300))
        return media
    }
    
    /// Returns location data for getAllMessages method according to its content.
    private func returnLocationData(_ content: String) -> Location? {
        let locationComponents = content.components(separatedBy: ",")
        
        guard let latitude = Double(locationComponents[0]),
              let longitude = Double(locationComponents[1])
        else { return nil }
        
        let location = Location(location: CLLocation(latitude: latitude, longitude: longitude),
                                size: CGSize(width: 300, height: 300))
        return location
    }
    
    /// Sends a message with target conversation and message
    public func sendMessage(to conversation: String, otherUserEmail: String, name: String, newMessage: Message, completion: @escaping (Bool) -> Void) {
        let currentEmail = returnSafeUserEmail()
        let currentName = returnUserName()
        
        database.child("\(conversation)/messages").observeSingleEvent(of: .value) { [weak self] snapshot in
            guard var currentMessages = snapshot.value as? [[String: Any]] else { completion(false); return }
            let messageDate = newMessage.sentDate
            let dateString = ChatViewController.dateFormatter.string(from: messageDate)
            var message = ""
            
            let updatedValue: [String: Any] = [
                "date": dateString,
                "is_read": false,
                "message": message
            ]
            
            let newConversationData: [String: Any] = [
                "id": conversation,
                "other_user_email": otherUserEmail,
                "name": name,
                "latest_message": updatedValue
            ]
            
            let conversationDataWithCurrentUserEmail: [String: Any] = [
                "id": conversation,
                "other_user_email": currentEmail,
                "name": currentName,
                "latest_message": updatedValue
            ]
            
            switch newMessage.kind {
            case .text(let messageText):
                message = messageText
            case .photo(let mediaItem):
                if let targetUrlString = mediaItem.url?.absoluteString {
                    message = targetUrlString
                }
            case .video(let mediaItem):
                if let targetUrlString = mediaItem.url?.absoluteString {
                    message = targetUrlString
                }
            case .location(let locationData):
                let location = locationData.location
                message = "\(location.coordinate.latitude),\(location.coordinate.longitude)"
            default:
                break
            }
            
            guard let newMessageEntry = self?.returnMessageCollection(
                id: newMessage.messageId,
                type: newMessage.kind.messageKindString,
                message: message,
                date: dateString,
                currentUserEmail: currentEmail,
                name: name)
            else { completion(false); return }
            
            currentMessages.append(newMessageEntry)
            
            self?.database.child("\(conversation)/messages").setValue(currentMessages) { error, _ in
                guard error == nil else { completion(false); return }
                
                self?.database.child("\(currentEmail)/conversations").observeSingleEvent(of: .value) { snapshot in
                    var databaseEntryConversations = [[String: Any]]()
                    if var currentUserConversations = snapshot.value as? [[String: Any]] {
                        
                        var targetConversation: [String: Any]?
                        var position = 0
                        
                        for conversationDictionary in currentUserConversations {
                            if let currentId = conversationDictionary["id"] as? String, currentId == conversation {
                                targetConversation = conversationDictionary
                                break
                            }
                            position += 1
                        }
                        
                        if var targetConversation = targetConversation {
                            targetConversation["latest_message"] = updatedValue
                            currentUserConversations[position] = targetConversation
                            databaseEntryConversations = currentUserConversations
                        }
                        else {
                            currentUserConversations.append(newConversationData)
                            databaseEntryConversations = currentUserConversations
                        }
                    }
                    else {
                        databaseEntryConversations = [ newConversationData ]
                    }
                    
                    self?.database.child("\(currentEmail)/conversations").setValue(databaseEntryConversations) { error, _ in
                        guard error == nil else { completion(false); return }
                        
                        // Update latest message for recipient
                        self?.database.child("\(otherUserEmail)/conversations").observeSingleEvent(of: .value) { snapshot in
                            var databaseEntryConversations = [[String: Any]]()
                            
                            if var otherUserConversations = snapshot.value as? [[String: Any]] {
                                var targetConversation: [String: Any]?
                                var position = 0
                                
                                for conversationDictionary in otherUserConversations {
                                    if let currentId = conversationDictionary["id"] as? String, currentId == conversation {
                                        targetConversation = conversationDictionary
                                        break
                                    }
                                    position += 1
                                }
                                
                                if var targetConversation = targetConversation {
                                    targetConversation["latest_message"] = updatedValue
                                    otherUserConversations[position] = targetConversation
                                    databaseEntryConversations = otherUserConversations
                                } else {
                                    otherUserConversations.append(conversationDataWithCurrentUserEmail)
                                    databaseEntryConversations = otherUserConversations
                                }
                            }
                            else {
                                databaseEntryConversations = [  conversationDataWithCurrentUserEmail ]
                            }
                            
                            self?.database.child("\(otherUserEmail)/conversations").setValue(databaseEntryConversations) { error, _ in
                                guard error == nil else {
                                    completion(false)
                                    return
                                }
                                completion(true)
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Deletes conversation for the user
    public func deleteConversation(conversationId: String, completion: @escaping (Bool) -> Void) {
        let safeEmail = returnSafeUserEmail()

        let databaseReference = database.child("\(safeEmail)/conversations")
        databaseReference.observeSingleEvent(of: .value) { snapshot in
            if var conversations = snapshot.value as? [[String: Any]] {
                var positionToRemove = 0
                for conversation in conversations {
                    if let id = conversation["id"] as? String, id == conversationId {
                        print("Found conversation to delete")
                        break
                    }
                    positionToRemove += 1
                }
                conversations.remove(at: positionToRemove)
                databaseReference.setValue(conversations) { error, _ in
                    guard error == nil else {
                        completion(false)
                        print("Failed to write new conversation array")
                        return
                    }
                    print("Successfully deleted conversation")
                    completion(true)
                }
            }
        }
    }
    
    /// Checks whether conversation exists or not
    public func conversationExists(with targetRecipientEmail: String, completion: @escaping (Result<String, Error>) -> Void) {
        let safeRecipientEmail = DatabaseManager.safeEmail(emailAddress: targetRecipientEmail)
        let safeSenderEmail = returnSafeUserEmail()
        database.child("\(safeRecipientEmail)/conversations").observeSingleEvent(of: .value) { snapshot in
            guard let collection = snapshot.value as? [[String: Any]] else {
                completion(.failure(DatabaseError.failedToFetch))
                return
            }
            
            if let conversation = collection.first(where: {
                guard let targetSenderEmail = $0["other_user_email"] as? String else { return false }
                return safeSenderEmail == targetSenderEmail
            }) {
                guard let id = conversation["id"] as? String else {
                    completion(.failure(DatabaseError.failedToFetch))
                    return
                }
                completion(.success(id))
                return
            }
            completion(.failure(DatabaseError.failedToFetch))
            return
        }
    }
}
