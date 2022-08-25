//
//  ProfileModels.swift
//  Messenger
//
//  Created by Michael Novosad on 25.08.2022.
//

import Foundation

enum ProfileViewModelType {
    case info, logout
}

struct ProfileViewModel {
    let viewModelType: ProfileViewModelType
    let title: String
    let handler: (() -> Void)?
}
