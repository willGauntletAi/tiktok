import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

admin.initializeApp();

// Import all functions
import { getRecommendations } from "./recommendations";
import { generateSong } from "./songs";
import { suggestEdits } from "./editSuggestions";

// Export all functions
export { getRecommendations, generateSong, suggestEdits };

// Update user document when it's created
export const onUserDocCreated = onDocumentCreated("users/{userId}", async (event) => {
  try {
    const snapshot = event.data;
    if (!snapshot) {
      console.error("No user data provided");
      return;
    }

    const userData = snapshot.data();
    if (!userData) return;

    // Update the user document with additional fields if needed
    await admin.firestore().collection("users").doc(snapshot.id).update({
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
  } catch (error) {
    console.error("Error updating user document:", error);
  }
});

// Example function to get user profile
export const getUserProfile = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  try {
    const userDoc = await admin.firestore().collection("users").doc(request.auth.uid).get();
    const userData = userDoc.data();

    if (!userData) {
      throw new HttpsError("not-found", "User profile not found");
    }

    return userData;
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "Error fetching user profile");
  }
});

// Function to handle notifications when a new like is created
export const onLikeCreated = onDocumentCreated("likes/{likeId}", async (event) => {
  try {
    const likeData = event.data?.data();
    if (!likeData) return;

    const postId = likeData.postId;
    const likerId = likeData.userId;

    // Get post details
    const postDoc = await admin.firestore().collection("posts").doc(postId).get();
    const postData = postDoc.data();
    if (!postData) return;

    // Don't send notification if user likes their own post
    if (postData.userId === likerId) return;

    // Get liker's user details
    const likerDoc = await admin.firestore().collection("users").doc(likerId).get();
    const likerData = likerDoc.data();
    if (!likerData) return;

    // Get post owner's FCM token
    const ownerDoc = await admin.firestore().collection("users").doc(postData.userId).get();
    const ownerData = ownerDoc.data();
    if (!ownerData?.fcmToken) return;

    // Send notification
    const message = {
      notification: {
        title: "New Like on Your Post",
        body: `${likerData.displayName} liked your post`
      },
      data: {
        postId: postId,
        type: "like"
      },
      token: ownerData.fcmToken
    };

    await admin.messaging().send(message);
  } catch (error) {
    console.error("Error sending like notification:", error);
  }
});

// Function to handle notifications when a new comment is created
export const onCommentCreated = onDocumentCreated("comments/{commentId}", async (event) => {
  try {
    const commentData = event.data?.data();
    if (!commentData) return;

    const postId = commentData.postId;
    const commenterId = commentData.userId;

    // Get post details
    const postDoc = await admin.firestore().collection("posts").doc(postId).get();
    const postData = postDoc.data();
    if (!postData) return;

    // Don't send notification if user comments on their own post
    if (postData.userId === commenterId) return;

    // Get commenter's user details
    const commenterDoc = await admin.firestore().collection("users").doc(commenterId).get();
    const commenterData = commenterDoc.data();
    if (!commenterData) return;

    // Get post owner's FCM token
    const ownerDoc = await admin.firestore().collection("users").doc(postData.userId).get();
    const ownerData = ownerDoc.data();
    if (!ownerData?.fcmToken) return;

    // Send notification
    const message = {
      notification: {
        title: "New Comment on Your Post",
        body: `${commenterData.displayName} commented: "${commentData.text.substring(0, 50)}${commentData.text.length > 50 ? "..." : ""}"`
      },
      data: {
        postId: postId,
        type: "comment"
      },
      token: ownerData.fcmToken
    };

    await admin.messaging().send(message);
  } catch (error) {
    console.error("Error sending comment notification:", error);
  }
});
