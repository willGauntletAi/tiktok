import FirebaseAuth
import SwiftUI

struct LoginView: View {
    @StateObject private var authService = AuthService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(isSignUp ? "Create Account" : "Welcome Back")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .disabled(isLoading)

                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(isLoading)

                Button(action: {
                    Task {
                        isLoading = true
                        do {
                            if isSignUp {
                                try await authService.signUp(email: email, password: password)
                            } else {
                                try await authService.signIn(email: email, password: password)
                            }
                        } catch {
                            showError = true
                            errorMessage = error.localizedDescription
                        }
                        isLoading = false
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(isSignUp ? "Sign Up" : "Sign In")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isLoading ? Color.blue.opacity(0.7) : Color.blue)
                    .cornerRadius(10)
                }
                .disabled(isLoading)

                Button(action: { isSignUp.toggle() }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .foregroundColor(.blue)
                }
                .disabled(isLoading)
            }
            .padding()
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
}
