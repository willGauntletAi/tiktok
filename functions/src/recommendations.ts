import { onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

interface Video {
    id: string;
    type: string;
    title: string;
    description: string;
    instructorId: string;
    videoUrl: string;
    thumbnailUrl: string;
    difficulty: string;
    targetMuscles: string[];
    createdAt: FirebaseFirestore.Timestamp;
    updatedAt: FirebaseFirestore.Timestamp;
}

interface RecommendationRequest {
    videoIds?: string[];
}

export const getRecommendations = onCall<RecommendationRequest>(async (request) => {
    try {
        const videoIds = request.data.videoIds || [];

        const db = admin.firestore();

        // Get videos to sample from
        const videosSnapshot = await db.collection("videos")
            .orderBy("createdAt")
            .limit(100)
            .get();

        const allVideos = videosSnapshot.docs.map(doc => ({
            id: doc.id,
            ...doc.data()
        })) as Video[];

        // Randomly select 5 videos
        const randomVideos: Video[] = [];
        const usedIndices = new Set<number>();

        while (randomVideos.length < 5 && usedIndices.size < allVideos.length) {
            const randomIndex = Math.floor(Math.random() * allVideos.length);
            if (!usedIndices.has(randomIndex)) {
                usedIndices.add(randomIndex);
                randomVideos.push(allVideos[randomIndex]);
            }
        }

        // If no input videos, just return the random ones
        if (videoIds.length === 0) {
            const recommendations = randomVideos.map(video => ({
                videoId: video.id,
                isOriginal: false,
                video
            }));
            return { recommendations };
        }

        // For each input video, randomly decide whether to keep it or use a random one
        const recommendations = videoIds.map((videoId, index) => {
            // Only consider replacement if we have a random video available for this index
            if (index < randomVideos.length) {
                const keepOriginal = Math.random() < 0.5;
                if (keepOriginal) {
                    return { videoId, isOriginal: true };
                } else {
                    return {
                        videoId: randomVideos[index].id,
                        isOriginal: false,
                        video: randomVideos[index]
                    };
                }
            } else {
                // If we don't have enough random videos, keep the original
                return { videoId, isOriginal: true };
            }
        });

        // Add remaining random videos until we have 5 total recommendations
        for (let i = recommendations.length; i < 5 && i < randomVideos.length; i++) {
            recommendations.push({
                videoId: randomVideos[i].id,
                isOriginal: false,
                video: randomVideos[i]
            });
        }

        return { recommendations };

    } catch (error) {
        console.error("Error in getRecommendations:", error);
        throw new Error("Failed to get recommendations");
    }
}); 