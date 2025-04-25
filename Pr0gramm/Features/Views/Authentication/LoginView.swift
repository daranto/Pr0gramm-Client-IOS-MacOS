// Pr0gramm/Pr0gramm/Features/Views/Authentication/LoginView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var captchaAnswer = ""
    @State private var isPasswordVisible = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Anmeldedaten") {
                    TextField("Benutzername", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        if isPasswordVisible {
                            TextField("Passwort", text: $password).textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                        } else {
                            SecureField("Passwort", text: $password).textContentType(.password)
                        }
                        Button { isPasswordVisible.toggle() } label: { Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill").foregroundColor(.secondary) }
                    }
                }

                // Captcha Section
                if authService.needsCaptcha {
                    Section("Captcha") {
                        if let captchaUiImage = authService.captchaImage {
                            Image(uiImage: captchaUiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 100, alignment: .center)
                                .padding(.vertical, 5)
                        } else {
                            HStack {
                                Spacer()
                                ProgressView()
                                Text("Lade Captcha...")
                                     .font(.footnote)
                                     .foregroundColor(.secondary)
                                Spacer()
                            }.frame(height: 50)
                        }
                        TextField("Captcha eingeben", text: $captchaAnswer)
                            .textContentType(.oneTimeCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { Task { await performLogin() } }
                    }
                }

                Section {
                    if let error = authService.loginError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                    Button { Task { await performLogin() } }
                    label: {
                        HStack { Spacer(); if authService.isLoading { ProgressView().progressViewStyle(.circular).tint(.white) } else { Text("Login") }; Spacer() }.padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authService.isLoading || username.isEmpty || password.isEmpty || (authService.needsCaptcha && captchaAnswer.isEmpty))
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Anmelden")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .onAppear {
                Task {
                    await authService.fetchInitialCaptcha()
                }
            }
        }
    }

    private func performLogin() async {
         await authService.login(
             username: username,
             password: password,
             captchaAnswer: authService.needsCaptcha ? captchaAnswer : nil
         )
         if authService.isLoggedIn {
             dismiss()
         }
     }
}

// --- Preview KORRIGIERT ---
#Preview {
    // Erstelle beide Services für die Preview
    let settings = AppSettings()
    let previewAuthService = AuthService(appSettings: settings) // Übergebe settings

    // Optional: Setze Testzustände für Captcha/Fehler
    // previewAuthService.needsCaptcha = true
    // previewAuthService.captchaImage = UIImage(systemName: "lock.shield")
    // previewAuthService.loginError = "Testfehler oder Captcha laden fehlgeschlagen."

    // Gib die View zurück (kein explizites 'return')
    LoginView()
        .environmentObject(previewAuthService)
        .environmentObject(settings) // Stelle auch settings bereit
}
// --- END OF COMPLETE FILE ---
