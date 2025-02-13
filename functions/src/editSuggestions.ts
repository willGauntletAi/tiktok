import * as functions from "firebase-functions";
import { onCall } from "firebase-functions/v2/https";
import { defineString } from "firebase-functions/params";
import { z } from "zod";
import {
    GoogleGenerativeAI,
    HarmCategory,
    HarmBlockThreshold,
    SafetySetting,
    Tool,
    SchemaType
} from "@google/generative-ai";

// Define the configuration parameter
const geminiApiKey = defineString("GEMINI_API_KEY");

// Initialize Gemini

// Zod schemas for our types
const ZoomConfigSchema = z.object({
    startZoomIn: z.number(),
    zoomInComplete: z.number().optional(),
    startZoomOut: z.number().optional(),
    zoomOutComplete: z.number().optional(),
    focusedJoint: z.string().optional()
});

const DetectedSetSchema = z.object({
    reps: z.number(),
    startTime: z.number(),
    endTime: z.number(),
    keyJoint: z.string()
});

const VideoClipStateSchema = z.object({
    id: z.number(),
    startTime: z.number(),
    endTime: z.number(),
    zoomConfig: ZoomConfigSchema.optional(),
    detectedSets: z.array(DetectedSetSchema).optional()
});

const EditorStateSchema = z.object({
    clips: z.array(VideoClipStateSchema),
    selectedClipIndex: z.number().optional()
});

// Define the edit action schemas
const SuggestedEditActionSchema = z.discriminatedUnion("type", [
    z.object({
        type: z.literal("deleteClip"),
        index: z.number()
    }),
    z.object({
        type: z.literal("moveClip"),
        from: z.number(),
        to: z.number()
    }),
    z.object({
        type: z.literal("swapClips"),
        index: z.number()
    }),
    z.object({
        type: z.literal("splitClip"),
        time: z.number()
    }),
    z.object({
        type: z.literal("trimClip"),
        clipId: z.string(),
        startTime: z.number(),
        endTime: z.number()
    }),
    z.object({
        type: z.literal("updateVolume"),
        clipId: z.string(),
        volume: z.number()
    }),
    z.object({
        type: z.literal("updateZoom"),
        clipId: z.string(),
        config: ZoomConfigSchema.nullable()
    })
]);

const EditActionSchema = z.discriminatedUnion("type", [
    z.object({
        type: z.literal("addClip"),
        clipId: z.string()
    }),
    ...SuggestedEditActionSchema.options
]);

const EditSuggestionSchema = z.object({
    action: SuggestedEditActionSchema,
    explanation: z.string(),
    confidence: z.number().min(0).max(1)
});

const EditHistoryEntrySchema = z.object({
    id: z.string(),
    title: z.string(),
    timestamp: z.number().transform((timestamp) => new Date(timestamp)),
    action: EditActionSchema,
    isApplied: z.boolean()
});

const EditSuggestionRequestSchema = z.object({
    prompt: z.string(),
    currentState: EditorStateSchema,
    editHistory: z.array(EditHistoryEntrySchema)
});

// Only keep the types we actually use
type EditSuggestionRequest = z.infer<typeof EditSuggestionRequestSchema>;
type EditSuggestion = z.infer<typeof EditSuggestionSchema>;

// Safety settings
const safetySettings: SafetySetting[] = [
    {
        category: HarmCategory.HARM_CATEGORY_HARASSMENT,
        threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE
    },
    {
        category: HarmCategory.HARM_CATEGORY_HATE_SPEECH,
        threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE
    },
    {
        category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
        threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE
    },
    {
        category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
        threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE
    }
];

// Function schema for Gemini
const geminiEditFunction: Tool = {
    functionDeclarations: [{
        name: "suggestEdit",
        description: "Suggest a single, specific edit to improve the video based on the current state and editing history",
        parameters: {
            type: SchemaType.OBJECT,
            properties: {
                action: {
                    type: SchemaType.OBJECT,
                    description: "The specific edit action to perform",
                    properties: {
                        type: {
                            type: SchemaType.STRING,
                            enum: ["deleteClip", "moveClip", "swapClips", "splitClip", "trimClip", "updateVolume", "updateZoom"],
                            description: "The type of edit action to perform"
                        },
                        index: {
                            type: SchemaType.NUMBER,
                            description: "Required for deleteClip and swapClips: The index of the clip to modify. This is the index of the clip in the currentState.clips array. It is zero-indexed."
                        },
                        from: {
                            type: SchemaType.NUMBER,
                            description: "Required for moveClip: Source index. This is the index of the clip in the currentState.clips array. It is zero-indexed."
                        },
                        to: {
                            type: SchemaType.NUMBER,
                            description: "Required for moveClip: Destination index. This is the index of the clip in the currentState.clips array. It is zero-indexed."
                        },
                        time: {
                            type: SchemaType.NUMBER,
                            description: "Required for splitClip: Time position to split at. This is the time in seconds from the start of the video, not the start of the clip."
                        },
                        clipId: {
                            type: SchemaType.STRING,
                            description: "Required for trimClip, updateVolume, updateZoom: ID of the clip to modify (string representation of numeric ID)"
                        },
                        startTime: {
                            type: SchemaType.NUMBER,
                            description: "Required for trimClip: New start time"
                        },
                        endTime: {
                            type: SchemaType.NUMBER,
                            description: "Required for trimClip: New end time"
                        },
                        volume: {
                            type: SchemaType.NUMBER,
                            description: "Required for updateVolume: New volume level (0-1)"
                        },
                        config: {
                            type: SchemaType.OBJECT,
                            description: "Required for updateZoom: Zoom configuration",
                            properties: {
                                startZoomIn: {
                                    type: SchemaType.NUMBER,
                                    description: "Required: When to start zooming in"
                                },
                                zoomInComplete: {
                                    type: SchemaType.NUMBER,
                                    description: "Optional: When zoom in completes"
                                },
                                startZoomOut: {
                                    type: SchemaType.NUMBER,
                                    description: "Optional: When to start zooming out"
                                },
                                zoomOutComplete: {
                                    type: SchemaType.NUMBER,
                                    description: "Optional: When zoom out completes"
                                },
                                focusedJoint: {
                                    type: SchemaType.STRING,
                                    description: "Optional: The joint to focus the zoom on (e.g. 'nose', 'leftEye', etc.)",
                                    enum: [
                                        "nose", "leftEye", "rightEye", "leftEar", "rightEar",
                                        "leftShoulder", "rightShoulder", "leftElbow", "rightElbow",
                                        "leftWrist", "rightWrist", "leftHip", "rightHip",
                                        "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"
                                    ]
                                }
                            },
                            required: ["startZoomIn"]
                        }
                    },
                    required: ["type"]
                },
                explanation: {
                    type: SchemaType.STRING,
                    description: "A clear explanation of why this edit would improve the video"
                },
                confidence: {
                    type: SchemaType.NUMBER,
                    description: "Confidence score (0-1) in this suggestion"
                }
            },
            required: ["action", "explanation", "confidence"]
        }
    }]
};

const generatePrompt = (request: EditSuggestionRequest): string => {
    const { prompt, currentState, editHistory } = request;

    return `You are an expert video editor AI assistant. Analyze the current state of the video and suggest ONE specific edit that would improve it.

CURRENT STATE:
${currentState.clips.map((clip, i) => `
Clip ${i + 1}:
- ID: ${clip.id}
- Duration: ${clip.endTime - clip.startTime}s
- Has zoom: ${clip.zoomConfig ? "Yes" : "No"}
${clip.detectedSets ? `- Exercise Sets:${clip.detectedSets.map(set => `
  • ${set.reps} reps from ${set.startTime.toFixed(1)}s to ${set.endTime.toFixed(1)}s (${set.keyJoint})`).join("")}` : "- No exercise sets detected"}
`).join("\n")}

EDIT HISTORY:
${editHistory.map(entry => `- ${entry.title} (${entry.isApplied ? "Applied" : "Undone"})`).join("\n")}

USER REQUEST:
${prompt}

Based on this information, suggest ONE specific edit that would most improve the video. Consider:
1. Pacing and flow between clips
2. Engagement and visual interest
3. Overall quality and polish
4. The user's specific request
5. Exercise set timing and transitions

When suggesting edits for exercise clips:
- Consider trimming dead time before/after exercise sets
- Suggest zooming during key exercise moments
- Maintain complete sets without splitting them
- Ensure transitions align with natural exercise boundaries

Provide your suggestion using the suggestEdit function, including:
- A specific, actionable edit
- A clear explanation of the improvement
- Confidence in the suggestion
- Expected impact on pacing, engagement, and quality`;
};

// Gemini generation config
const generationConfig = {
    temperature: 0.7,
    topK: 40,
    topP: 0.95,
    maxOutputTokens: 1024,
};

// Add max retries constant
const MAX_RETRIES = 3;

// Add helper function to generate error feedback prompt
const generateErrorFeedbackPrompt = (originalPrompt: string, error: Error): string => {
    return `${originalPrompt}

PREVIOUS ATTEMPT FAILED WITH ERROR:
The previous suggestion was invalid because: ${error.message}

Please provide a new suggestion that follows the schema requirements exactly. Pay special attention to:
- Including all required fields for the chosen action type
- Using the correct data types for all fields
- Ensuring numeric values are valid
- Following the schema structure exactly`;
};

export const suggestEdits = onCall(
    {
        timeoutSeconds: 120,
        memory: "256MiB"
    },
    async (request): Promise<{ suggestions: EditSuggestion[] }> => {

        const genAI = new GoogleGenerativeAI(geminiApiKey.value() || "");
        const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });
        const data = request.data;

        try {
            // Validate request using Zod schema
            EditSuggestionRequestSchema.parse(data);

            // Generate initial prompt
            let currentPrompt = generatePrompt(data);
            let attempts = 0;

            while (attempts < MAX_RETRIES) {
                try {
                    console.log(`Attempt ${attempts + 1} of ${MAX_RETRIES}`);

                    // Get response from Gemini
                    const result = await model.generateContent({
                        contents: [{ role: "user", parts: [{ text: currentPrompt }] }],
                        generationConfig,
                        safetySettings,
                        tools: [geminiEditFunction]
                    });

                    const geminiResponse = await result.response;
                    console.log("Full Gemini response:", JSON.stringify(geminiResponse, null, 2));

                    const functionCall = geminiResponse.candidates?.[0]?.content?.parts?.[0]?.functionCall;
                    console.log("Function call data:", JSON.stringify(functionCall, null, 2));

                    if (!functionCall || functionCall.name !== "suggestEdit") {
                        throw new Error("No valid edit suggestion received");
                    }

                    // Parse and validate the suggestion
                    console.log("Raw function args:", typeof functionCall.args, functionCall.args);
                    const suggestion = typeof functionCall.args === "string"
                        ? JSON.parse(functionCall.args)
                        : functionCall.args;
                    console.log("Parsed suggestion:", JSON.stringify(suggestion, null, 2));

                    // Preprocess numeric fields
                    if (suggestion.action.type === "trimClip") {
                        suggestion.action.startTime = Number(suggestion.action.startTime);
                        suggestion.action.endTime = Number(suggestion.action.endTime);
                    }
                    if (suggestion.action.type === "updateVolume") {
                        suggestion.action.volume = Number(suggestion.action.volume);
                    }
                    if (suggestion.action.type === "splitClip") {
                        suggestion.action.time = Number(suggestion.action.time);
                    }
                    if (suggestion.confidence) {
                        suggestion.confidence = Number(suggestion.confidence);
                    }

                    const validatedSuggestion = EditSuggestionSchema.parse(suggestion);

                    // If we get here, validation succeeded
                    return {
                        suggestions: [validatedSuggestion]
                    };

                } catch (error) {
                    attempts++;
                    console.log(`Attempt ${attempts} failed:`, error);

                    // If we've exhausted retries, throw the last error
                    if (attempts >= MAX_RETRIES) {
                        throw error;
                    }

                    // Update prompt with error feedback for next attempt
                    currentPrompt = generateErrorFeedbackPrompt(
                        generatePrompt(data),
                        error instanceof Error ? error : new Error(String(error))
                    );
                }
            }

            // This should never be reached due to the throw in the retry loop
            throw new Error("Unexpected end of retry loop");

        } catch (error) {
            console.error("Error generating suggestion:", error);
            throw new functions.https.HttpsError(
                "internal",
                "Error generating edit suggestion",
                error
            );
        }
    }
); 