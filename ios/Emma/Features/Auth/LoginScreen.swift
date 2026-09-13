import SwiftUI

// MARK: - Logowanie i blokada
//
// Dwa ekrany przed aplikacją:
//   • `LoginScreen` — demonstracyjne logowanie (e-mail + hasło). Raz, dopóki
//     użytkownik się nie wyloguje.
//   • `LockScreen` — odblokowanie Face ID / hasłem urządzenia przy każdym wejściu.
//
// Oba są celowo spokojne i mówią wprost, co się dzieje: demo nie udaje
// prawdziwego systemu kont, a brak biometrii nie udaje, że Face ID zadziałało.

struct LoginScreen: View {

    @EnvironmentObject private var auth: AuthStore

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        AuthScaffold(
            orbActive: false,
            title: "Emma",
            caption: "KANCELARIA ROGOŻA",
            headline: "Zaloguj się",
            message: "Jedno wspólne konto zespołu — te same sprawy i zadania dla wszystkich."
        ) {
            VStack(spacing: 14) {
                LabeledField("E-mail") {
                    TextField("imie@kancelaria.pl", text: $email)
                        .focused($focusedField, equals: .email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .modifier(AuthFieldStyle())
                }

                LabeledField("Hasło") {
                    SecureField("Hasło", text: $password)
                        .focused($focusedField, equals: .password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                        .modifier(AuthFieldStyle())
                }

                if let notice = auth.notice {
                    Text(notice)
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PrimaryButton("Zaloguj się", systemImage: "arrow.right") {
                    submit()
                }
                .padding(.top, 4)
            }
        } footer: {
            Text("Wersja demonstracyjna: dane konta nie są nigdzie wysyłane, wystarczy dowolny e-mail i hasło.")
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { focusedField = .email }
    }

    private func submit() {
        focusedField = nil
        auth.signIn(email: email, password: password)
    }
}

// MARK: - Ekran blokady

struct LockScreen: View {

    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        AuthScaffold(
            orbActive: true,
            title: "Zablokowane",
            caption: "EMMA",
            headline: "Witaj ponownie",
            message: "Odblokuj, aby wrócić do spraw, rozmów i terminarza."
        ) {
            VStack(spacing: 12) {
                PrimaryButton(
                    auth.unlockButtonTitle,
                    systemImage: auth.canUseBiometrics ? "faceid" : "lock.open",
                    isEnabled: !auth.isAuthenticating,
                    action: { Task { await auth.unlock() } }
                )

                if let notice = auth.notice {
                    Text(notice)
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecondaryButton("Wyloguj się", systemImage: "rectangle.portrait.and.arrow.right") {
                    auth.signOut()
                }
            }
        } footer: {
            if let unavailable = auth.availabilityNotice {
                Text("\(unavailable) W wersji demonstracyjnej dostęp odblokowuje przycisk powyżej.")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Dane kancelarii zostają na urządzeniu — blokada chroni tylko dostęp do aplikacji.")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Odblokowanie biometryczne startuje samo; przycisk zostaje dla przypadku,
        // gdy Face ID jest niedostępne albo użytkownik je odrzuci.
        .task {
            if auth.canUseBiometrics { await auth.unlock() }
        }
    }
}

// MARK: - Wspólna oprawa

/// Wspólny układ obu ekranów: orb, tytuł, komunikat, treść i stopka.
private struct AuthScaffold<Content: View, Footer: View>: View {

    let orbActive: Bool
    let title: String
    let caption: String
    let headline: String
    let message: String
    let content: Content
    let footer: Footer

    init(
        orbActive: Bool,
        title: String,
        caption: String,
        headline: String,
        message: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.orbActive = orbActive
        self.title = title
        self.caption = caption
        self.headline = headline
        self.message = message
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                EmmaOrb(size: .hero, isActive: orbActive, breathing: true)
                    .padding(.top, 44)
                    .padding(.bottom, 26)

                Text(title)
                    .font(EmmaTypography.heading(26))
                    .tracking(-0.8)
                    .foregroundStyle(EmmaTheme.ink)

                Text(caption)
                    .font(EmmaTypography.kicker)
                    .tracking(1.5)
                    .foregroundStyle(EmmaTheme.mutedSoft)
                    .padding(.top, 6)
                    .padding(.bottom, 30)

                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(EmmaTypography.heading(19))
                        .foregroundStyle(EmmaTheme.ink)
                    Text(message)
                        .font(EmmaTypography.ui(13))
                        .foregroundStyle(EmmaTheme.muted)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 22)

                content

                footer
                    .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: 430)
            .frame(maxWidth: .infinity)
        }
        .background(EmmaTheme.bg)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Wygląd pola tekstowego spójny z polami formularzy (`.form-field input`).
private struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(EmmaTypography.ui(15))
            .foregroundStyle(EmmaTheme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.button, style: .continuous)
                    .strokeBorder(EmmaTheme.composerBorder, lineWidth: 1)
            }
    }
}

#Preview("Logowanie") {
    LoginScreen()
        .environmentObject(AuthStore(authenticator: PreviewBiometricAuthenticator(), defaults: UserDefaults(suiteName: "preview.login")!))
}

#Preview("Blokada") {
    LockScreen()
        .environmentObject(AuthStore(authenticator: PreviewBiometricAuthenticator(result: true), defaults: UserDefaults(suiteName: "preview.lock")!))
}
