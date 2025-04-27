import SwiftUI

/// A view presented as a sheet for user login, handling username, password, and captcha input.
struct LoginView: View {
    @EnvironmentObject var authService: AuthService // Access authentication logic and state
    @Environment(\.dismiss) var dismiss // Action to close the sheet

    @State private var username = ""
    @State private var password = ""
    @State private var captchaAnswer = ""
    @State private var isPasswordVisible = false // Toggle password visibility

    var body: some View {
        NavigationStack {
            Form {
                // Section for standard login credentials
                Section("Anmeldedaten") {
                    TextField("Benutzername", text: $username)
                        .textContentType(.username) // Autofill hint
                        .textInputAutocapitalization(.never) // Disable capitalization
                        .autocorrectionDisabled()
                    HStack {
                        // Conditionally show SecureField or TextField for password
                        if isPasswordVisible {
                            TextField("Passwort", text: $password)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Passwort", text: $password)
                                .textContentType(.password) // Autofill hint
                        }
                        // Button to toggle password visibility
                        Button { isPasswordVisible.toggle() } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Section for Captcha (shown only if required by AuthService)
                if authService.needsCaptcha {
                    Section("Captcha") {
                        if let captchaUiImage = authService.captchaImage {
                            // Display the captcha image
                            Image(uiImage: captchaUiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 100, alignment: .center)
                                .padding(.vertical, 5)
                        } else {
                            // Show loading indicator while captcha image loads
                            HStack {
                                Spacer()
                                ProgressView()
                                Text("Lade Captcha...")
                                     .font(.footnote)
                                     .foregroundColor(.secondary)
                                Spacer()
                            }.frame(height: 50) // Maintain consistent height
                        }
                        // Input field for the captcha answer
                        TextField("Captcha eingeben", text: $captchaAnswer)
                            .textContentType(.oneTimeCode) // Autofill hint (might work)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            // Allow submitting login via keyboard return key
                            .onSubmit { Task { await performLogin() } }
                    }
                }

                // Section for Login Button and Error Message
                Section {
                    // Display login error message if present
                    if let error = authService.loginError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                    // Login Button
                    Button { Task { await performLogin() } }
                    label: {
                        HStack {
                            Spacer()
                            // Show ProgressView while loading
                            if authService.isLoading {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                            } else {
                                Text("Login")
                            }
                            Spacer()
                        }.padding(.vertical, 8) // Add padding for better tap area
                    }
                    .buttonStyle(.borderedProminent) // Use prominent style
                    // Disable button during loading or if required fields are empty
                    .disabled(authService.isLoading || username.isEmpty || password.isEmpty || (authService.needsCaptcha && captchaAnswer.isEmpty))
                }
                .listRowBackground(Color.clear) // Remove default background for button section
            }
            .navigationTitle("Anmelden")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Add a Cancel button to dismiss the sheet
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .onAppear {
                // Fetch initial captcha state when the view appears
                Task {
                    await authService.fetchInitialCaptcha()
                }
            }
        }
    }

    /// Calls the AuthService to perform the login attempt. Dismisses the view on success.
    private func performLogin() async {
         await authService.login(
             username: username,
             password: password,
             captchaAnswer: authService.needsCaptcha ? captchaAnswer : nil // Pass captcha only if needed
         )
         // Dismiss the sheet automatically if login was successful
         if authService.isLoggedIn {
             dismiss()
         }
     }
}

// MARK: - Preview

#Preview {
    // Setup necessary services for the preview
    let settings = AppSettings()
    let previewAuthService = AuthService(appSettings: settings)

    // Optional: Simulate different states for previewing
    // previewAuthService.needsCaptcha = true
    // previewAuthService.captchaImage = UIImage(systemName: "lock.shield") // Use a system image as placeholder
    // previewAuthService.loginError = "Testfehler: Captcha falsch."
    // previewAuthService.isLoading = true

    // Provide the services to the LoginView
    return LoginView()
        .environmentObject(previewAuthService)
        // Although LoginView doesn't *directly* use settings,
        // AuthService does, so providing it here ensures the preview environment is complete.
        .environmentObject(settings)
}
