import Foundation
import Observation

/// Port de lib/i18n.ts (español / inglés), más portugués y ruso.
enum Lang: String, CaseIterable, Identifiable {
    case es, en, pt, ru

    var id: String { rawValue }
    var name: String {
        switch self {
        case .es: "Español"
        case .en: "English"
        case .pt: "Português"
        case .ru: "Русский"
        }
    }
}

@MainActor
@Observable
final class Localizer {
    var lang: Lang {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: "lang") }
    }

    init() {
        lang = Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "") ?? .es
    }

    func t(_ key: L) -> String {
        let table: [L: String] = switch lang {
        case .es: Self.es
        case .en: Self.en
        case .pt: Self.pt
        case .ru: Self.ru
        }
        return table[key] ?? Self.en[key] ?? key.rawValue
    }

    func pick(_ es: String, _ en: String, _ pt: String, _ ru: String) -> String {
        switch lang {
        case .es: es
        case .en: en
        case .pt: pt
        case .ru: ru
        }
    }

    /// Plural ruso: 1 файл, 2 файла, 5 файлов.
    private func ru(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }

    // MARK: - Con parámetros

    func entriesInHistory(_ n: Int) -> String {
        pick("\(n) \(n == 1 ? "entrada" : "entradas") en el historial",
             "\(n) \(n == 1 ? "entry" : "entries") in history",
             "\(n) \(n == 1 ? "entrada" : "entradas") no histórico",
             "\(n) \(ru(n, "запись", "записи", "записей")) в истории")
    }
    func selectedCount(_ current: Int, _ max: Int) -> String {
        pick("\(current) de \(max) seleccionados. Revisa el lote antes de subir.",
             "\(current) of \(max) selected. Review the batch before uploading.",
             "\(current) de \(max) selecionados. Revise o lote antes de enviar.",
             "Выбрано \(current) из \(max). Проверьте пакет перед загрузкой.")
    }
    func maxFiles(_ max: Int) -> String {
        pick("Máximo \(max) archivos por lote.", "Maximum \(max) files per batch.",
             "Máximo de \(max) arquivos por lote.", "Не более \(max) файлов за раз.")
    }
    func addedSome(_ added: Int, _ skipped: Int, _ max: Int) -> String {
        pick("Se añadieron \(added). \(skipped) quedaron fuera del límite de \(max).",
             "Added \(added). \(skipped) were skipped (limit of \(max)).",
             "\(added) adicionados. \(skipped) ficaram fora do limite de \(max).",
             "Добавлено: \(added). Пропущено: \(skipped) (лимит \(max)).")
    }
    func confirmUpload(_ n: Int) -> String {
        pick("Confirmar y subir (\(n))", "Confirm and upload (\(n))", "Confirmar e enviar (\(n))", "Подтвердить и загрузить (\(n))")
    }
    func deletedEntries(_ n: Int) -> String {
        pick("Se eliminaron \(n) entradas", "Deleted \(n) entries", "\(n) entradas excluídas",
             "Удалено \(n) \(ru(n, "запись", "записи", "записей"))")
    }
    func totalVotes(_ n: Int) -> String {
        pick("\(n) \(n == 1 ? "voto" : "votos") en total", "\(n) \(n == 1 ? "vote" : "votes") in total",
             "\(n) \(n == 1 ? "voto" : "votos") no total", "Всего \(n) \(ru(n, "голос", "голоса", "голосов"))")
    }
    func imagesSaved(_ n: Int) -> String {
        pick("\(n) imágenes guardadas", "\(n) images saved", "\(n) imagens salvas",
             "Сохранено \(n) \(ru(n, "изображение", "изображения", "изображений"))")
    }
    func filesSaved(_ n: Int) -> String {
        pick("\(n) archivos guardados", "\(n) files saved", "\(n) arquivos salvos",
             "Сохранено \(n) \(ru(n, "файл", "файла", "файлов"))")
    }
    func itemsSaved(_ n: Int) -> String {
        pick("\(n) elementos guardados", "\(n) items saved", "\(n) itens salvos",
             "Сохранено \(n) \(ru(n, "элемент", "элемента", "элементов"))")
    }
    func partiallySaved(_ n: Int) -> String {
        pick("Se guardaron \(n), pero falló el resto", "Saved \(n), but the rest failed",
             "\(n) salvos, mas o resto falhou", "Сохранено \(n), остальные — с ошибкой")
    }
    func confirmRemoveFriend(_ email: String) -> String {
        pick("¿Eliminar a \(email) de tus amigos?", "Remove \(email) from your friends?",
             "Remover \(email) dos seus amigos?", "Удалить \(email) из друзей?")
    }
    func shareSend(_ n: Int) -> String { pick("Enviar (\(n))", "Send (\(n))", "Enviar (\(n))", "Отправить (\(n))") }
    func sharedWith(_ n: Int) -> String {
        n == 1
            ? pick("Enviado a 1 amigo", "Sent to 1 friend", "Enviado para 1 amigo", "Отправлено 1 другу")
            : pick("Enviado a \(n) amigos", "Sent to \(n) friends", "Enviado para \(n) amigos",
                   "Отправлено \(n) \(ru(n, "другу", "друзьям", "друзьям"))")
    }
    func sharePartial(_ ok: Int, _ total: Int) -> String {
        pick("Enviado a \(ok) de \(total) amigos", "Sent to \(ok) of \(total) friends",
             "Enviado para \(ok) de \(total) amigos", "Отправлено \(ok) из \(total) друзей")
    }
    func receivedFrom(_ email: String) -> String {
        pick("Recibido de \(email)", "Received from \(email)", "Recebido de \(email)", "Получено от \(email)")
    }
    func menuLastCapture(_ time: String) -> String {
        pick("Última captura: \(time)", "Last capture: \(time)", "Última captura: \(time)", "Последний захват: \(time)")
    }

    // MARK: - Fechas (lib/utils.ts)

    var locale: Locale { Locale(identifier: lang.rawValue) }

    func relative(_ date: Date) -> String {
        let sec = Int((Date().timeIntervalSince(date)).rounded())
        if sec < 45 { return pick("Ahora", "Now", "Agora", "Сейчас") }
        let min = Int((Double(sec) / 60).rounded())
        if min < 60 { return pick("Hace \(min) min", "\(min)m ago", "Há \(min) min", "\(min) мин назад") }
        let hrs = Int((Double(min) / 60).rounded())
        if hrs < 24 { return pick("Hace \(hrs) h", "\(hrs)h ago", "Há \(hrs) h", "\(hrs) ч назад") }
        let days = Int((Double(hrs) / 24).rounded())
        if days < 7 { return pick("Hace \(days) d", "\(days)d ago", "Há \(days) d", "\(days) дн. назад") }
        return date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
    }

    func detailed(_ date: Date) -> String {
        date.formatted(
            .dateTime.weekday(.abbreviated).year().month(.abbreviated).day()
                .hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits).second(.twoDigits)
                .locale(locale)
        )
    }

    // MARK: - Diccionarios

    static let es: [L: String] = [
        .brandSubtitle: "Tu historial sync",
        .navHistory: "Historial", .navAdd: "Agregar", .navSettings: "Configuración", .navAbout: "Acerca de",
        .account: "Cuenta", .logout: "Salir",
        .filterAll: "Todo", .filterText: "Texto", .filterImages: "Imágenes", .filterFiles: "Archivos",
        .searchPlaceholder: "Buscar en el historial…",
        .loadingHistory: "Cargando historial…",
        .emptyTitle: "Sin entradas aún",
        .emptyBody: "Agrega texto, imágenes o archivos (PDF, DOCX, XLSX), o copia algo: la app captura el clipboard automáticamente.",
        .addNow: "Agregar ahora",
        .textType: "Texto", .imageType: "Imagen", .fileType: "Archivo", .chars: "chars",
        .seeLess: "Ver menos", .seeMore: "Ver completo",
        .download: "Descargar", .copied: "Copiado", .copy: "Copiar", .open: "Abrir", .delete: "Eliminar",
        .text: "Texto", .draftPlaceholder: "Escribe o pega texto…", .saveText: "Guardar texto",
        .chooseFiles: "Elegir archivos", .pasteFromClipboard: "Pegar del portapapeles",
        .confirmFiles: "Confirmar archivos", .addMore: "Añadir más",
        .filesOnly: "Solo se admiten imágenes, PDF, DOCX o XLSX.", .filesHint: "Imágenes, PDF, DOCX y XLSX. También puedes arrastrarlos aquí.",
        .cancel: "Cancelar",
        .signInTitle: "Iniciar sesión", .signUpTitle: "Crear cuenta",
        .email: "Email", .password: "Contraseña",
        .authErrorSignIn: "No se pudo iniciar sesión. Revisa email y contraseña.",
        .authErrorSignUp: "No se pudo crear la cuenta. ¿Ya existe ese email?",
        .wait: "Espera…", .signIn: "Entrar", .signUp: "Registrarme",
        .noAccount: "¿No tienes cuenta?", .createOne: "Crear una", .haveAccount: "¿Ya tienes cuenta?", .signInNow: "Iniciar sesión",
        .accountDetails: "Detalles de la cuenta",
        .changePassword: "Cambiar contraseña", .minChars: "Mínimo 8 caracteres.",
        .currentPassword: "Contraseña actual", .newPassword: "Nueva contraseña", .confirmNewPassword: "Confirmar nueva",
        .passwordsMismatch: "Las contraseñas nuevas no coinciden",
        .passwordTooShort: "La nueva contraseña debe tener al menos 8 caracteres",
        .passwordUpdated: "Contraseña actualizada", .passwordFailed: "No se pudo cambiar la contraseña",
        .saving: "Guardando…", .updatePassword: "Actualizar contraseña",
        .encryptionPasswordNote: "Al cambiarla también se reenvuelve la clave de cifrado.",
        .deleteData: "Borrar datos",
        .deleteDataBody: "Elimina todos los textos e imágenes del historial de esta cuenta. No se puede deshacer.",
        .nothingToDelete: "No había datos que borrar", .clearFailed: "No se pudieron borrar los datos",
        .deleting: "Borrando…", .confirmDelete: "Confirmar borrado", .deleteAllHistory: "Borrar todo el historial",
        .version: "Versión",
        .aboutBody: "Clipboard Cloud guarda tu portapapeles y tus capturas de pantalla, cifrados en tu Mac, y los sincroniza con la misma cuenta en la web y en tus otros dispositivos.",
        .permissionsTitle: "Permisos",
        .permissionDesktop: "Escritorio: para subir las capturas de ⌘⇧3 / ⌘⇧4 que macOS guarda ahí. Las que van al portapapeles (⌃⌘⇧4) no lo necesitan.",
        .language: "Idioma", .languageSubtitle: "Cambia el idioma de la aplicación.",
        .pollTitle: "Tu opinión", .loadingPoll: "Cargando encuesta…",
        .excellent: "Excelente", .good: "Buena", .regular: "Regular", .bad: "Mala",
        .submit: "Enviar", .view: "Ver", .back: "Volver",
        .loadingSession: "Cargando sesión…",
        .textSaved: "Texto guardado", .textSaveFailed: "No se pudo guardar el texto",
        .imageSaved: "Imagen guardada", .fileSaved: "Archivo guardado",
        .filesSaveFailed: "No se pudieron guardar los archivos", .deleteFailed: "No se pudo eliminar",
        .copiedToClipboard: "Copiado al portapapeles", .imageCopied: "Imagen copiada al portapapeles",
        .imageCopyFailed: "No se pudo copiar la imagen", .oneEntryDeleted: "Se eliminó 1 entrada",
        .openFailed: "No se pudo abrir",
        .encryptionUnlockTitle: "Desbloquear cifrado",
        .encryptionUnlockBody: "Tu historial está cifrado. Solo tu contraseña puede descifrarlo; Convex no puede leer el contenido.",
        .encryptionUnlock: "Desbloquear", .encryptionUnlockFailed: "No se pudo desbloquear. Revisa la contraseña.",
        .decryptFailed: "No se pudo descifrar esta entrada.",
        .encryptionActiveNote: "Textos e imágenes se cifran en tu dispositivo. En Convex solo se guarda ciphertext.",
        .desktopMonitor: "Monitor de escritorio",
        .desktopMonitorBody: "Captura el clipboard y screenshots cada pocos segundos.",
        .pauseMonitor: "Pausar", .resumeMonitor: "Reanudar",
        .monitorStatus: "Estado", .monitorActive: "Activo", .monitorPaused: "Pausado", .monitorInterval: "Intervalo",
        .lastClipboard: "Último clipboard", .lastScreenshot: "Última captura",
        .friends: "Amigos", .friendsSubtitle: "Invita amigos por correo y comparte entradas cifradas.",
        .friendsTabFriends: "Amigos", .friendsTabIncoming: "Recibidas", .friendsTabOutgoing: "Enviadas",
        .inviteByEmail: "Invitar por correo", .invitePlaceholder: "correo@ejemplo.com", .inviteSend: "Invitar",
        .inviteSent: "Invitación enviada", .inviteAccepted: "Invitación aceptada: ya son amigos",
        .inviteInvalidEmail: "Correo no válido", .inviteSelf: "No puedes invitarte a ti mismo",
        .inviteAlreadyFriends: "Ya son amigos", .inviteAlreadyInvited: "Ya enviaste una invitación a ese correo",
        .inviteFailed: "No se pudo enviar la invitación",
        .inviteHint: "Si aún no tiene cuenta, verá la invitación al registrarse con ese correo.",
        .noFriends: "Aún no tienes amigos. Invita a alguien por correo.",
        .noIncoming: "No tienes invitaciones pendientes.", .noOutgoing: "No has enviado invitaciones pendientes.",
        .accept: "Aceptar", .decline: "Rechazar", .cancelInvite: "Cancelar", .removeFriend: "Eliminar",
        .notRegistered: "Sin cuenta aún", .friendNoKey: "Debe abrir la app para poder recibir",
        .friendActionFailed: "No se pudo completar la acción", .friendAccepted: "Amigo agregado",
        .close: "Cerrar", .share: "Compartir", .shareTitle: "Compartir con amigos", .sharing: "Enviando…",
        .shareNoFriends: "Agrega amigos para poder compartir.", .shareFailed: "No se pudo compartir",
        .unknownUser: "usuario desconocido", .decryptPending: "Preparando claves…",
        .menuShow: "Mostrar Clipboard Cloud", .menuPause: "Pausar monitoreo", .menuResume: "Reanudar monitoreo",
        .menuSignIn: "Inicia sesión para sincronizar", .menuUnlock: "Desbloquea el cifrado en la app",
        .menuSessionActive: "Sesión activa", .menuCopyLatest: "Copiar último registro", .menuScreenshotPermission: "Permiso para capturas…", .menuQuit: "Salir",
    ]

    static let en: [L: String] = [
        .brandSubtitle: "Sync history",
        .navHistory: "History", .navAdd: "Add", .navSettings: "Settings", .navAbout: "About",
        .account: "Account", .logout: "Log out",
        .filterAll: "All", .filterText: "Text", .filterImages: "Images", .filterFiles: "Files",
        .searchPlaceholder: "Search history…",
        .loadingHistory: "Loading history…",
        .emptyTitle: "No entries yet",
        .emptyBody: "Add text, images or files (PDF, DOCX, XLSX), or copy something: the app captures the clipboard automatically.",
        .addNow: "Add now",
        .textType: "Text", .imageType: "Image", .fileType: "File", .chars: "chars",
        .seeLess: "See less", .seeMore: "See full",
        .download: "Download", .copied: "Copied", .copy: "Copy", .open: "Open", .delete: "Delete",
        .text: "Text", .draftPlaceholder: "Type or paste text…", .saveText: "Save text",
        .chooseFiles: "Choose files", .pasteFromClipboard: "Paste from clipboard",
        .confirmFiles: "Confirm files", .addMore: "Add more",
        .filesOnly: "Only images, PDF, DOCX or XLSX are allowed.", .filesHint: "Images, PDF, DOCX and XLSX. You can also drag them here.",
        .cancel: "Cancel",
        .signInTitle: "Sign in", .signUpTitle: "Create account",
        .email: "Email", .password: "Password",
        .authErrorSignIn: "Could not sign in. Check email and password.",
        .authErrorSignUp: "Could not create the account. Does that email already exist?",
        .wait: "Wait…", .signIn: "Enter", .signUp: "Sign up",
        .noAccount: "No account?", .createOne: "Create one", .haveAccount: "Already have an account?", .signInNow: "Sign in",
        .accountDetails: "Account details",
        .changePassword: "Change password", .minChars: "Minimum 8 characters.",
        .currentPassword: "Current password", .newPassword: "New password", .confirmNewPassword: "Confirm new password",
        .passwordsMismatch: "New passwords do not match",
        .passwordTooShort: "New password must be at least 8 characters",
        .passwordUpdated: "Password updated", .passwordFailed: "Could not change the password",
        .saving: "Saving…", .updatePassword: "Update password",
        .encryptionPasswordNote: "Changing it also re-wraps your encryption key.",
        .deleteData: "Delete data",
        .deleteDataBody: "Deletes all texts and images from this account's history. This cannot be undone.",
        .nothingToDelete: "There was no data to delete", .clearFailed: "Could not delete the data",
        .deleting: "Deleting…", .confirmDelete: "Confirm delete", .deleteAllHistory: "Delete all history",
        .version: "Version",
        .aboutBody: "Clipboard Cloud saves your clipboard and screenshots, encrypted on your Mac, and syncs them with the same account on the web and your other devices.",
        .permissionsTitle: "Permissions",
        .permissionDesktop: "Desktop: to upload the ⌘⇧3 / ⌘⇧4 screenshots macOS saves there. Screenshots sent to the clipboard (⌃⌘⇧4) don't need it.",
        .language: "Language", .languageSubtitle: "Switch the language of the app.",
        .pollTitle: "Your feedback", .loadingPoll: "Loading poll…",
        .excellent: "Excellent", .good: "Good", .regular: "Fair", .bad: "Poor",
        .submit: "Submit", .view: "View", .back: "Back",
        .loadingSession: "Loading session…",
        .textSaved: "Text saved", .textSaveFailed: "Could not save the text",
        .imageSaved: "Image saved", .fileSaved: "File saved",
        .filesSaveFailed: "Could not save the files", .deleteFailed: "Could not delete",
        .copiedToClipboard: "Copied to clipboard", .imageCopied: "Image copied to clipboard",
        .imageCopyFailed: "Could not copy the image", .oneEntryDeleted: "Deleted 1 entry",
        .openFailed: "Could not open",
        .encryptionUnlockTitle: "Unlock encryption",
        .encryptionUnlockBody: "Your history is encrypted. Only your password can decrypt it; Convex cannot read the content.",
        .encryptionUnlock: "Unlock", .encryptionUnlockFailed: "Could not unlock. Check your password.",
        .decryptFailed: "Could not decrypt this entry.",
        .encryptionActiveNote: "Texts and images are encrypted on your device. Convex only stores ciphertext.",
        .desktopMonitor: "Desktop monitor",
        .desktopMonitorBody: "Captures the clipboard and screenshots every few seconds.",
        .pauseMonitor: "Pause", .resumeMonitor: "Resume",
        .monitorStatus: "Status", .monitorActive: "Active", .monitorPaused: "Paused", .monitorInterval: "Interval",
        .lastClipboard: "Last clipboard", .lastScreenshot: "Last screenshot",
        .friends: "Friends", .friendsSubtitle: "Invite friends by email and share encrypted entries.",
        .friendsTabFriends: "Friends", .friendsTabIncoming: "Received", .friendsTabOutgoing: "Sent",
        .inviteByEmail: "Invite by email", .invitePlaceholder: "email@example.com", .inviteSend: "Invite",
        .inviteSent: "Invitation sent", .inviteAccepted: "Invitation accepted: you are now friends",
        .inviteInvalidEmail: "Invalid email", .inviteSelf: "You cannot invite yourself",
        .inviteAlreadyFriends: "You are already friends", .inviteAlreadyInvited: "You already invited that email",
        .inviteFailed: "Could not send the invitation",
        .inviteHint: "If they have no account yet, they will see it after signing up with that email.",
        .noFriends: "No friends yet. Invite someone by email.",
        .noIncoming: "No pending invitations.", .noOutgoing: "No pending sent invitations.",
        .accept: "Accept", .decline: "Decline", .cancelInvite: "Cancel", .removeFriend: "Remove",
        .notRegistered: "No account yet", .friendNoKey: "Must open the app to receive",
        .friendActionFailed: "Could not complete the action", .friendAccepted: "Friend added",
        .close: "Close", .share: "Share", .shareTitle: "Share with friends", .sharing: "Sending…",
        .shareNoFriends: "Add friends to be able to share.", .shareFailed: "Could not share",
        .unknownUser: "unknown user", .decryptPending: "Preparing keys…",
        .menuShow: "Show Clipboard Cloud", .menuPause: "Pause monitoring", .menuResume: "Resume monitoring",
        .menuSignIn: "Sign in to sync", .menuUnlock: "Unlock encryption in the app",
        .menuSessionActive: "Session active", .menuCopyLatest: "Copy latest entry", .menuScreenshotPermission: "Screenshot permission…", .menuQuit: "Quit",
    ]
}

enum L: String {
    case brandSubtitle
    case navHistory, navAdd, navSettings, navAbout, account, logout
    case filterAll, filterText, filterImages, filterFiles, searchPlaceholder
    case loadingHistory, emptyTitle, emptyBody, addNow
    case textType, imageType, fileType, chars, seeLess, seeMore
    case download, copied, copy, open, delete
    case text, draftPlaceholder, saveText, chooseFiles, pasteFromClipboard, confirmFiles, addMore
    case filesOnly, filesHint, cancel
    case signInTitle, signUpTitle, email, password, authErrorSignIn, authErrorSignUp
    case wait, signIn, signUp, noAccount, createOne, haveAccount, signInNow
    case accountDetails, changePassword, minChars, currentPassword, newPassword, confirmNewPassword
    case passwordsMismatch, passwordTooShort, passwordUpdated, passwordFailed, saving, updatePassword
    case encryptionPasswordNote
    case deleteData, deleteDataBody, nothingToDelete, clearFailed, deleting, confirmDelete, deleteAllHistory
    case version, aboutBody, permissionsTitle, permissionDesktop
    case language, languageSubtitle
    case pollTitle, loadingPoll, excellent, good, regular, bad, submit, view, back
    case loadingSession, textSaved, textSaveFailed, imageSaved, fileSaved, filesSaveFailed
    case deleteFailed, copiedToClipboard, imageCopied, imageCopyFailed, oneEntryDeleted, openFailed
    case encryptionUnlockTitle, encryptionUnlockBody, encryptionUnlock, encryptionUnlockFailed
    case decryptFailed, encryptionActiveNote
    case desktopMonitor, desktopMonitorBody, pauseMonitor, resumeMonitor
    case monitorStatus, monitorActive, monitorPaused, monitorInterval, lastClipboard, lastScreenshot
    case friends, friendsSubtitle, friendsTabFriends, friendsTabIncoming, friendsTabOutgoing
    case inviteByEmail, invitePlaceholder, inviteSend, inviteSent, inviteAccepted
    case inviteInvalidEmail, inviteSelf, inviteAlreadyFriends, inviteAlreadyInvited, inviteFailed, inviteHint
    case noFriends, noIncoming, noOutgoing, accept, decline, cancelInvite, removeFriend
    case notRegistered, friendNoKey, friendActionFailed, friendAccepted
    case close, share, shareTitle, sharing, shareNoFriends, shareFailed
    case unknownUser, decryptPending
    case menuShow, menuPause, menuResume, menuSignIn, menuUnlock, menuSessionActive
    case menuScreenshotPermission, menuQuit, menuCopyLatest
}
