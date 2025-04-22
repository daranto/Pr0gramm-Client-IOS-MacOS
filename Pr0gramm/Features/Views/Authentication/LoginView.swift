// LoginView.swift

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
                // needsCaptcha wird jetzt durch onAppear gesetzt
                if authService.needsCaptcha {
                    Section("Captcha") {
                        if let captchaUiImage = authService.captchaImage {
                            Image(uiImage: captchaUiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 100, alignment: .center)
                                .padding(.vertical, 5)
                                // Optional: Tap to refresh captcha?
                                // .onTapGesture { Task { await authService.fetchInitialCaptcha() } }
                        } else {
                            HStack { // Ladeanzeige
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
                    // Fehlermeldung (wird jetzt auch gesetzt, wenn Captcha-Laden fehlschlägt)
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
                    // Login-Button ist deaktiviert, wenn Captcha benötigt wird, aber die Antwort fehlt
                    .disabled(authService.isLoading || username.isEmpty || password.isEmpty || (authService.needsCaptcha && captchaAnswer.isEmpty))
                }
                .listRowBackground(Color.clear) // Keine Trennlinien/Hintergrund für Button-Section
            }
            .navigationTitle("Anmelden")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            // Captcha beim Erscheinen holen
            .onAppear {
                Task {
                    await authService.fetchInitialCaptcha()
                }
            }
        }
    }

    /// Logik für den Login-Button ausgelagert
    private func performLogin() async {
         // Übergebe die aktuelle Captcha-Antwort, wenn needsCaptcha true ist
         await authService.login(
             username: username,
             password: password,
             captchaAnswer: authService.needsCaptcha ? captchaAnswer : nil // Wichtig!
         )
         // Schließe das Sheet nur, wenn der Login erfolgreich war
         if authService.isLoggedIn {
             dismiss()
         } else {
             // Optional: Captcha-Feld leeren nach fehlgeschlagenem Versuch?
             // captchaAnswer = ""
         }
     }
}

// Previews bleiben wie zuvor, verwenden jetzt den aktualisierten AuthService
#Preview {
    let previewAuthService = AuthService()
    // Zum Testen der Captcha Section in der Preview:
    // Task { await previewAuthService.fetchInitialCaptcha() } // würde echtes Captcha holen
    // ODER manuell setzen:
    // previewAuthService.needsCaptcha = true
    // previewAuthService.captchaImage = UIImage(systemName: "lock.shield") // Dummy-Bild
    // previewAuthService.loginError = "Testfehler oder Captcha laden fehlgeschlagen."

    return LoginView()
        .environmentObject(previewAuthService)
}
