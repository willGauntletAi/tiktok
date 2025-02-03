import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { beforeUserCreated } from 'firebase-functions/v2/identity';
import * as admin from 'firebase-admin';

admin.initializeApp();

// Create a new user document when a user signs up
export const onUserCreated = beforeUserCreated(async (event) => {
    try {
        const user = event.data;
        if (!user) {
            console.error('No user data provided');
            return { customClaims: {} };
        }

        await admin.firestore().collection('users').doc(user.uid).set({
            uid: user.uid,
            email: user.email || null,
            displayName: user.displayName || null,
            photoURL: user.photoURL || null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { customClaims: {} };
    } catch (error) {
        console.error('Error creating user document:', error);
        return { customClaims: {} };
    }
});

// Example function to get user profile
export const getUserProfile = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    try {
        const userDoc = await admin.firestore().collection('users').doc(request.auth.uid).get();
        const userData = userDoc.data();

        if (!userData) {
            throw new HttpsError('not-found', 'User profile not found');
        }

        return userData;
    } catch (error) {
        if (error instanceof HttpsError) {
            throw error;
        }
        throw new HttpsError('internal', 'Error fetching user profile');
    }
}); 
