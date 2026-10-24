import SwiftUI
import ClerkKit

private enum AuthMode { case logIn, signUp }
private enum CodePhase { case signUp, deviceTrust }

struct LoginView: View {
    @Environment(Clerk.self) private var clerk
    @State private var mode: AuthMode = .logIn
    @State private var codePhase: CodePhase?
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var code = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var errorMessage = ""

    private var cleanEmail: String { email.trimmingCharacters(in:.whitespacesAndNewlines) }
    private var validEmail: Bool {
        let pattern = #"^[A-Z0-9a-z._%+\-]+@[A-Z0-9a-z](?:[A-Z0-9a-z\-]*[A-Z0-9a-z])?(?:\.[A-Z0-9a-z](?:[A-Z0-9a-z\-]*[A-Z0-9a-z])?)+$"#
        return cleanEmail.range(of:pattern,options:.regularExpression) != nil
    }
    private var passwordRules: [(String,Bool)] {
        let scalars = password.unicodeScalars
        return [
            ("At least 15 characters", password.count >= 15),
            ("An uppercase letter", scalars.contains { CharacterSet.uppercaseLetters.contains($0) }),
            ("A lowercase letter", scalars.contains { CharacterSet.lowercaseLetters.contains($0) }),
            ("A number", scalars.contains { CharacterSet.decimalDigits.contains($0) }),
            ("A special character", scalars.contains { CharacterSet.punctuationCharacters.union(.symbols).contains($0) })
        ]
    }
    private var strongPassword: Bool { passwordRules.allSatisfy(\.1) }
    private var canSubmit: Bool {
        validEmail && !busy && (mode == .logIn ? !password.isEmpty : strongPassword && confirmPassword == password)
    }

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                VStack(alignment:.leading,spacing:12) {
                    Image("toodle-logo-teal").renderingMode(.template).resizable().scaledToFit()
                        .foregroundStyle(Tok.logoTeal).frame(width:96,height:64)
                    KineticText(codePhase == nil ? "Welcome to Toodle" : "Check your email",size:36,style:.largeTitle,extrude:true)
                    Text(codePhase == nil ? "Sign in to monitor the city." : "Enter the code we sent to \(cleanEmail).")
                        .foregroundStyle(Tok.inkMuted)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(Tok.Space.lg).textZone()
                if codePhase == nil { credentialsForm }
                else { verificationForm }
            }.padding(24).frame(maxWidth:480).frame(maxWidth:.infinity)
        }.serifBody().foregroundStyle(Tok.ink).foilScreen().tint(Tok.accent)
    }

    private var credentialsForm: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
            Text("Email").modifier(KineticFont(weight:650,opsz:17,size:17,style:.headline))
                Spacer()
            }
            TextField("you@example.com",text:$email,prompt:Text("you@example.com").foregroundStyle(Tok.inkMuted))
                .keyboardType(.emailAddress).textContentType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.plain).foregroundStyle(Tok.ink).padding(10)
                .background(Tok.panel,in:RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Tok.line,lineWidth:1))
                .accessibilityLabel("Email address")
            if !email.isEmpty && !validEmail {
                Text("Enter a valid email address.").serifCaption().foregroundStyle(Tok.strongBlue)
                    .accessibilityIdentifier("emailError")
            }
            Text("Password").modifier(KineticFont(weight:650,opsz:17,size:17,style:.headline))
            HStack {
                Group {
                    if showPassword { TextField("Password",text:$password,prompt:Text("Password").foregroundStyle(Tok.inkMuted)) }
                    else { SecureField("Password",text:$password,prompt:Text("Password").foregroundStyle(Tok.inkMuted)) }
                }.textContentType(mode == .signUp ? .newPassword : .password)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .foregroundStyle(Tok.ink).accessibilityLabel("Password")
                Button(showPassword ? "Hide" : "Show") { showPassword.toggle() }
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
            }.padding(10).background(Tok.panel,in:RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Tok.line,lineWidth:1))
            if mode == .signUp {
                VStack(alignment:.leading,spacing:6) {
                    ForEach(passwordRules,id:\.0) { title,passed in
                        Label(title,systemImage:passed ? "checkmark.circle.fill" : "circle")
                            .serifCaption().foregroundStyle(passed ? Tok.accent : Tok.inkMuted)
                    }
                }.accessibilityElement(children:.combine)
                Text("Confirm password").modifier(KineticFont(weight:650,opsz:17,size:17,style:.headline))
                if showPassword { TextField("Confirm password",text:$confirmPassword,prompt:Text("Confirm password").foregroundStyle(Tok.inkMuted)).foregroundStyle(Tok.ink).textFieldStyle(.roundedBorder) }
                else { SecureField("Confirm password",text:$confirmPassword,prompt:Text("Confirm password").foregroundStyle(Tok.inkMuted)).foregroundStyle(Tok.ink).textFieldStyle(.roundedBorder) }
                if !confirmPassword.isEmpty && confirmPassword != password {
                    Text("Passwords do not match.").serifCaption().foregroundStyle(Tok.strongBlue)
                }
            }
            if !errorMessage.isEmpty { errorText }
            Button(mode == .signUp ? "Sign Up" : "Log In") { Task { await submit() } }
                .buttonStyle(.toodle).frame(maxWidth:.infinity)
                .disabled(!canSubmit).accessibilityIdentifier("authSubmit")
            if busy { ReactionLoading(title:"Please wait…") }
            Button(mode == .signUp ? "Already have an account? Log In" : "New to Toodle? Sign Up") {
                mode = mode == .signUp ? .logIn : .signUp
                password = ""; confirmPassword = ""; errorMessage = ""; showPassword = false
            }.frame(maxWidth:.infinity)
        }.card()
    }

    private var verificationForm: some View {
        VStack(alignment:.leading,spacing:16) {
            TextField("Email code",text:$code,prompt:Text("Email code").foregroundStyle(Tok.inkMuted))
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .foregroundStyle(Tok.ink).textFieldStyle(.roundedBorder).accessibilityLabel("Email verification code")
            if !errorMessage.isEmpty { errorText }
            Button("Verify Email") { Task { await verifyCode() } }
                .buttonStyle(.toodle)
                .disabled(code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || busy)
            Button("Resend code") { Task { await resendCode() } }.disabled(busy)
            Button("Back") { codePhase = nil; code = ""; errorMessage = "" }.disabled(busy)
            if busy { ReactionLoading(title:"Please wait…") }
        }.card()
    }

    private var errorText: some View {
        Text(errorMessage).foregroundStyle(Tok.strongBlue)
            .accessibilityIdentifier("authError")
    }

    private func submit() async {
        guard canSubmit else { return }
        busy = true; errorMessage = ""
        defer { busy = false }
        do {
            if mode == .signUp {
                let signUp = try await clerk.auth.signUp(emailAddress:cleanEmail,password:password)
                try await signUp.sendEmailCode()
                codePhase = .signUp
            } else {
                let signIn = try await clerk.auth.signInWithPassword(identifier:cleanEmail,password:password)
                switch signIn.status {
                case .complete: password = ""
                case .needsClientTrust:
                    _ = try await signIn.sendMfaEmailCode()
                    codePhase = .deviceTrust
                default: errorMessage = "This account needs an additional sign-in step. Check your Clerk settings."
                }
            }
        } catch { show(error) }
    }

    private func verifyCode() async {
        guard !busy else { return }
        busy = true; errorMessage = ""
        defer { busy = false }
        do {
            switch codePhase {
            case .signUp:
                guard let signUp = clerk.auth.currentSignUp else { errorMessage = "Start sign-up again to request a new code."; return }
                try await signUp.verifyEmailCode(code.trimmingCharacters(in:.whitespacesAndNewlines))
            case .deviceTrust:
                guard let signIn = clerk.auth.currentSignIn else { errorMessage = "Log in again to request a new code."; return }
                let verified = try await signIn.verifyMfaCode(code.trimmingCharacters(in:.whitespacesAndNewlines),type:.emailCode)
                guard verified.status == .complete else { errorMessage = "Verification is not complete yet."; return }
            case nil: return
            }
            password = ""; confirmPassword = ""; code = ""; codePhase = nil
        } catch { show(error) }
    }

    private func resendCode() async {
        guard !busy else { return }
        busy = true; errorMessage = ""
        defer { busy = false }
        do {
            switch codePhase {
            case .signUp:
                guard let signUp = clerk.auth.currentSignUp else { errorMessage = "Start sign-up again to request a new code."; return }
                try await signUp.sendEmailCode()
            case .deviceTrust:
                guard let signIn = clerk.auth.currentSignIn else { errorMessage = "Log in again to request a new code."; return }
                _ = try await signIn.sendMfaEmailCode()
            case nil: return
            }
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        if let clerkError = error as? ClerkAPIError {
            errorMessage = clerkError.errorDescription ?? clerkError.localizedDescription
        } else { errorMessage = error.localizedDescription }
    }
}
