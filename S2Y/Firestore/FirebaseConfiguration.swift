//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Spezi
import SpeziAccount


final class FirebaseConfiguration: Module, DefaultInitializable, @unchecked Sendable {
    enum ConfigurationError: Error {
        case userNotAuthenticatedYet
    }
    
    static var userCollection: CollectionReference {
        Firestore.firestore().collection("users")
    }
    
    
    @Dependency(Account.self) private var account: Account? // optional, as Firebase might be disabled
    
    
    @MainActor var userDocumentReference: DocumentReference {
        get throws {
            // Prefer the authenticated Firebase UID to satisfy security rules
            if let uid = Auth.auth().currentUser?.uid {
                return Self.userCollection.document(uid)
            }
            // Fallback to account details if available
            guard let details = account?.details else {
                throw ConfigurationError.userNotAuthenticatedYet
            }
            return userDocumentReference(for: details.accountId)
        }
    }
    
    @MainActor var userBucketReference: StorageReference {
        get throws {
            guard let details = account?.details else {
                throw ConfigurationError.userNotAuthenticatedYet
            }
            
            return Storage.storage().reference().child("users/\(details.accountId)")
        }
    }
    
    
    init() {}
    
    
    func userDocumentReference(for accountId: String) -> DocumentReference {
        Self.userCollection.document(accountId)
    }
    
}
