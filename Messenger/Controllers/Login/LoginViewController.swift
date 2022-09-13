//
//  LoginViewController.swift
//  Messenger
//
//  Created by Michael Novosad on 05.08.2022.
//

import UIKit
import FirebaseAuth
import FBSDKLoginKit
import GoogleSignIn
import Firebase
import JGProgressHUD

final class LoginViewController: UIViewController {
    
    private let spinner = JGProgressHUD(style: .dark)
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.clipsToBounds = true
        return scrollView
    }()
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "logo-1")
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let emailField: UITextField = {
        let emailField = UITextField()
        emailField.autocorrectionType = .no
        emailField.autocapitalizationType = .none
        emailField.returnKeyType = .continue
        emailField.layer.cornerRadius = 12
        emailField.layer.borderWidth = 1
        emailField.layer.borderColor = UIColor.lightGray.cgColor
        emailField.placeholder = "Email Address..."
        emailField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 5, height: 0))
        emailField.leftViewMode = .always
        emailField.backgroundColor = .secondarySystemBackground
        return emailField
    }()
    
    private let passwordField: UITextField = {
        let passwordField = UITextField()
        passwordField.autocorrectionType = .no
        passwordField.autocapitalizationType = .none
        passwordField.isSecureTextEntry = true
        passwordField.returnKeyType = .done
        passwordField.layer.cornerRadius = 12
        passwordField.layer.borderWidth = 1
        passwordField.layer.borderColor = UIColor.lightGray.cgColor
        passwordField.placeholder = "Password..."
        passwordField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 5, height: 0))
        passwordField.leftViewMode = .always
        passwordField.backgroundColor = .secondarySystemBackground
        return passwordField
    }()
    
    private let loginButton: UIButton = {
        let button = UIButton()
        button.setTitle("Log In", for: .normal)
        button.backgroundColor = .link
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.masksToBounds = true
        button.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        return button
    }()
    
    private let facebookLoginButton: FBLoginButton = {
        let loginButton = FBLoginButton()
        loginButton.layer.cornerRadius = 12
        loginButton.layer.masksToBounds = true
        loginButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        loginButton.permissions = ["email", "public_profile"]
        return loginButton
    }()
    
    private let googleLoginButton: GIDSignInButton = {
        let googleButton = GIDSignInButton()
        googleButton.layer.cornerRadius = 12
        googleButton.layer.masksToBounds = true
        googleButton.style = .wide
        return googleButton
    }()
    
    private var loginObserver: NSObjectProtocol?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loginObserver = NotificationCenter.default.addObserver(forName: .didLogInNotification,
                                                               object: nil,
                                                               queue: .main) { [weak self] _ in
            self?.navigationController?.dismiss(animated: true)
        }
        
        title = "Log In"
        view.backgroundColor = .systemBackground
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Register",
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(didTapRegister))
        
        loginButton.addTarget(self,
                              action: #selector(loginButtonTapped),
                              for: .touchUpInside)
        
        googleLoginButton.addTarget(self,
                                    action: #selector(signUpWithGoogle),
                                    for: .touchUpInside)
        
        emailField.delegate = self
        passwordField.delegate = self
        
        facebookLoginButton.delegate = self
        
        // Add subviews
        view.addSubview(scrollView)
        scrollView.addSubview(imageView)
        scrollView.addSubview(emailField)
        scrollView.addSubview(passwordField)
        scrollView.addSubview(loginButton)
        scrollView.addSubview(facebookLoginButton)
        scrollView.addSubview(googleLoginButton)
    }
    
    deinit {
        if let observer = loginObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        let size = scrollView.width/4
        
        imageView.frame = CGRect(x: (scrollView.width-size)/2,
                                 y: 20,
                                 width: size,
                                 height: size)
        
        emailField.frame = CGRect(x: 30,
                                  y: imageView.bottom+30,
                                  width: scrollView.width-60,
                                  height: 52)
        
        passwordField.frame = CGRect(x: 30,
                                     y: emailField.bottom+10,
                                     width: scrollView.width-60,
                                     height: 52)
        
        loginButton.frame = CGRect(x: 30,
                                   y: passwordField.bottom+10,
                                   width: scrollView.width-60,
                                   height: 52)
        
        facebookLoginButton.frame = CGRect(x: 30,
                                           y: loginButton.bottom+10,
                                           width: scrollView.width-60,
                                           height: 52)
        
        googleLoginButton.frame = CGRect(x: 30,
                                         y: facebookLoginButton.bottom+10,
                                         width: scrollView.width-60,
                                         height: 52)
    }
    
    @objc
    private func loginButtonTapped() {
        emailField.resignFirstResponder()
        passwordField.resignFirstResponder()
        
        guard let email = emailField.text,
              let password = passwordField.text,
              !email.isEmpty,
              !password.isEmpty,
              password.count >= 6 else {
            alertUserLoginError()
            return
        }
        
        spinner.show(in: view, animated: true)
        
        //Firebase Log In
        FirebaseAuth.Auth.auth().signIn(withEmail: email, password: password) { [weak self] authResult, error in
            
            DispatchQueue.main.async {
                self?.spinner.dismiss(animated: true)
            }
            
            guard let result = authResult,
                  error == nil else {
                print("Error logging in user with email: \(email), password: \(password)")
                return
            }
            
            let user = result.user
            
            let safeEmail = DatabaseManager.safeEmail(emailAddress: email)
            DatabaseManager.shared.getDataFor(path: safeEmail) { result in
                switch result {
                case .success(let data):
                    guard let userData = data as? [String: Any],
                          let firstName = userData["first_name"] as? String,
                          let lastName = userData["last_name"] as? String else { return }
                    UserDefaults.standard.set("\(firstName) \(lastName)", forKey: "name")
                    
                case .failure(let error):
                    print("Failed to read data with error \(error)")
                }
            }
            
            UserDefaults.standard.set(email, forKey: "email")

            print("Logged In User: \(user)")
            self?.navigationController?.dismiss(animated: true)
        }
    }
    
    func alertUserLoginError() {
        let alert = UIAlertController(title: "Woops",
                                      message: "Please enter all information to log in.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Dismiss",
                                      style: .cancel))
        present(alert, animated: true)
    }
    
    @objc
    private func didTapRegister() {
        let vc = RegisterViewController()
        vc.title = "Create Account"
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension LoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        if textField == emailField {
            passwordField.becomeFirstResponder()
        } else if textField == passwordField {
            loginButtonTapped()
        }
        
        return true
    }
}
// MARK: - Facebook sign in
extension LoginViewController: LoginButtonDelegate {
    func loginButton(_ loginButton: FBLoginButton, didCompleteWith result: LoginManagerLoginResult?, error: Error?) {
        guard let token = result?.token?.tokenString else {
            print("User failed to Log In with Facebook")
            return
        }
        
        let facebookRequest = FBSDKLoginKit.GraphRequest(graphPath: "me",
                                                         parameters: ["fields": "email, first_name, last_name, picture.type(large)"],
                                                         tokenString: token,
                                                         version: nil,
                                                         httpMethod: .get)
        
        facebookRequest.start { [weak self] connection, result, error in
            guard let result = result as? [String: Any], error == nil else {
                print("Failed to make Facebook graph request")
                return
            }
            
            guard let firstName = result["first_name"] as? String,
                  let lastName = result["last_name"] as? String,
                  let email = result["email"] as? String,
            let picture = result["picture"] as? [String: Any],
            let data = picture["data"] as? [String: Any],
            let pictureUrl = data["url"] as? String else {
                print("Failed to get name and email from Facebook")
                return
            }
            
            UserDefaults.standard.set(email, forKey: "email")
            UserDefaults.standard.set("\(firstName) \(lastName)", forKey: "name")

            print(result)
            DatabaseManager.shared.userExists(with: email) { exists in
                if !exists {
                    let chatUser = ChatAppUser(firstName: firstName,
                                               lastName: lastName,
                                               emailAddress: email)
                    DatabaseManager.shared.insertUser(with: chatUser) { success in
                        if success {
                            guard let url = URL(string: pictureUrl) else { return }
                            
                            print("Downloading data from facebook image")
                            
                            URLSession.shared.dataTask(with: url) { data, _, _ in
                                guard let data = data else {
                                    print("Failed to get data from facebook")
                                    return
                                }
                                
                                print("Got data from facebook, uploading...")
                                let fileName = chatUser.profilePictureFileName
                                StorageManager.shared.uploadProfilePicture(with: data, fileName: fileName) { result in
                                    switch result {
                                    case .success(let downloadUrl):
                                        UserDefaults.standard.set(downloadUrl, forKey: "profile_picture_url")
                                        print(downloadUrl)
                                    case .failure(let error):
                                        print("Storage manager error: \(error)")
                                    }
                                }
                            }.resume()
                        }
                    }
                }
            }
            
            let credential = FacebookAuthProvider.credential(withAccessToken: token)
            
            FirebaseAuth.Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                guard authResult != nil, error == nil else {
                    if let error = error {
                        print("Facebook credential login failed, MFA may be needed - \(error)")
                    }
                    return
                }
                
                print("Successfully Logged In via Facebook")
                self?.navigationController?.dismiss(animated: true)
            }
        }
        
    }
    
    func loginButtonDidLogOut(_ loginButton: FBLoginButton) {
        // no operation
    }
    
}

// MARK: - Google sign in
extension LoginViewController {
    @objc
    public func signUpWithGoogle() {
        guard let firebaseClientID = FirebaseApp.app()?.options.clientID else {
            print("Could not get firebaseClientID")
            return
        }
        let googleConfiguration = GIDConfiguration(clientID: firebaseClientID)
        
        GIDSignIn.sharedInstance.signIn(with: googleConfiguration, presenting: self) { user, error in
            guard
                error == nil,
                let user = user
            else { return }
            
            user.authentication.do { authentication, error in
                guard
                    error == nil,
                    let authentication = authentication,
                    let idToken = authentication.idToken
                else {
                    print("Unable to get google authentication id token")
                    return
                }
                
                print("Did sign in with Google: \(user)")
                
                guard let email = user.profile?.email,
                      let firstName = user.profile?.givenName,
                      let lastName = user.profile?.familyName
                else {
                    print("Missing auth object of google user")
                    return
                }
                
                UserDefaults.standard.set(email, forKey: "email")
                UserDefaults.standard.set("\(firstName) \(lastName)", forKey: "name")

                DatabaseManager.shared.userExists(with: email) { exists in
                    if !exists {
                        let chatUser = ChatAppUser(firstName: firstName,
                                                   lastName: lastName,
                                                   emailAddress: email)
                        DatabaseManager.shared.insertUser(with: chatUser) { success in
                            if success {
                                
                                if let userProfile = user.profile {
                                    if userProfile.hasImage {
                                        guard let url = userProfile.imageURL(withDimension: 200) else { return }
                                        
                                        URLSession.shared.dataTask(with: url) { data, _, _ in
                                            guard let data = data else {
                                                return
                                            }
                                            
                                            let fileName = chatUser.profilePictureFileName
                                            StorageManager.shared.uploadProfilePicture(with: data, fileName: fileName) { result in
                                                switch result {
                                                case .success(let downloadUrl):
                                                    UserDefaults.standard.set(downloadUrl, forKey: "profile_picture_url")
                                                    print(downloadUrl)
                                                case .failure(let error):
                                                    print("Storage manager error: \(error)")
                                                }
                                            }
                                        }.resume()
                                    }
                                }
                            }
                        }
                    }
                }
                
                let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                               accessToken: authentication.accessToken)
                FirebaseAuth.Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                    guard authResult != nil, error == nil else {
                        if let error = error {
                            print("Google credential login failed - \(error)")
                        }
                        return
                    }
                    print("Successfully Signed In via Google")
                    NotificationCenter.default.post(name: .didLogInNotification, object: nil)
                    self?.navigationController?.dismiss(animated: true)
                }
            }
        }
    }
}
