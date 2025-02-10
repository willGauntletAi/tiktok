import { onCall, HttpsError } from "firebase-functions/v2/https";
import Replicate from "replicate";
import { defineString } from "firebase-functions/params";
import * as admin from "firebase-admin";
import fetch from "node-fetch";

// Initialize Firebase Admin if it hasn't been initialized yet
if (!admin.apps.length) {
    admin.initializeApp();
}

// Define the configuration parameter
const replicateApiToken = defineString("REPLICATE_API_TOKEN");

interface SongGenerationResponse {
    success: boolean;
    message: string;
    data: {
        songId: string;
        tags: string[];
        lyrics: string;
        status: "pending" | "completed" | "failed";
        storageRef?: string;
        error?: string;
    }
}

export const generateSong = onCall({
    timeoutSeconds: 1800, // 30 minutes
    memory: "1GiB", // Increase memory as song generation might be memory intensive
}, async (request) => {
    // Validate authentication
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const { tags, lyrics, title = "Generated Song" } = request.data;
    const startTime = Date.now();

    // Set up progress logging
    const progressInterval = setInterval(() => {
        const elapsedMinutes = Math.floor((Date.now() - startTime) / 60000);
        const elapsedSeconds = Math.floor((Date.now() - startTime) / 1000) % 60;
        console.log(`[${title}] Time elapsed: ${elapsedMinutes}m ${elapsedSeconds}s`);
    }, 30000); // Log every 30 seconds

    try {
        // Validate input
        if (!Array.isArray(tags) || tags.length === 0) {
            clearInterval(progressInterval);
            throw new HttpsError("invalid-argument", "Tags must be a non-empty array of strings");
        }

        if (typeof lyrics !== "string" || lyrics.trim().length === 0) {
            clearInterval(progressInterval);
            throw new HttpsError("invalid-argument", "Lyrics must be a non-empty string");
        }

        // Initialize Replicate client with the parameter
        const replicate = new Replicate({
            auth: replicateApiToken.value()
        });

        // Combine tags into a genre description
        const genreDescription = tags.join(" ");

        console.log(`[${title}] Starting song generation...`);

        // Call Replicate API to generate song with only the required parameters
        const output = await replicate.run(
            "fofr/yue:f45da0cfbe372eb9116e87a1e3519aceb008fd03b0d771d21fb8627bee2b4117",
            {
                input: {
                    lyrics: lyrics,
                    genre_description: genreDescription
                }
            }
        );

        console.log(`[${title}] Song generated, downloading...`);

        // Handle the output type more safely
        if (!output || typeof output !== "string") {
            clearInterval(progressInterval);
            throw new Error("Invalid response from Replicate API");
        }

        // Download the generated song
        const downloadResponse = await fetch(output);
        if (!downloadResponse.ok) {
            clearInterval(progressInterval);
            throw new Error("Failed to download generated song");
        }
        const buffer = await downloadResponse.buffer();

        console.log(`[${title}] Download complete, uploading to storage...`);

        // Create a unique filename
        const timestamp = Date.now();
        const filename = `songs/${request.auth.uid}/${timestamp}.mp3`;

        // Upload to Firebase Storage
        const bucket = admin.storage().bucket();
        const file = bucket.file(filename);
        await file.save(buffer, {
            metadata: {
                contentType: "audio/mpeg",
            }
        });

        // Get the public URL
        await file.makePublic();
        const storageRef = `gs://${bucket.name}/${filename}`;

        console.log(`[${title}] Upload complete, creating database entry...`);

        // Create a new song document in Firestore
        const songDoc = admin.firestore().collection("songs").doc();
        const songData = {
            id: songDoc.id,
            title,
            storageRef,
            tags,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        };

        await songDoc.set(songData);

        // Calculate total time taken
        const totalMinutes = Math.floor((Date.now() - startTime) / 60000);
        const totalSeconds = Math.floor((Date.now() - startTime) / 1000) % 60;
        console.log(`[${title}] Completed in ${totalMinutes}m ${totalSeconds}s`);

        clearInterval(progressInterval);

        const result: SongGenerationResponse = {
            success: true,
            message: "Song generated and stored successfully",
            data: {
                songId: songDoc.id,
                tags,
                lyrics,
                status: "completed",
                storageRef
            }
        };

        return result;

    } catch (error) {
        clearInterval(progressInterval);
        console.error(`[${title}] Error generating song:`, error);

        const errorResponse: SongGenerationResponse = {
            success: false,
            message: "Failed to generate song",
            data: {
                songId: "",
                tags,
                lyrics,
                status: "failed",
                error: error instanceof Error ? error.message : "Unknown error occurred"
            }
        };

        throw new HttpsError("internal", "Failed to generate song", errorResponse);
    }
}); 