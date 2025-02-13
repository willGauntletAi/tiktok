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

// Function schemas for Gemini
const geminiEditFunctions: Tool[] = [
    {
        functionDeclarations: [{
            name: "deleteClip",
            description: "Delete a clip from the video",
            parameters: {
                type: SchemaType.OBJECT,
                properties: {
                    index: {
                        type: SchemaType.NUMBER,
                        description: "The index of the clip to delete. This is the index of the clip in the currentState.clips array. It is zero-indexed."
                    },
                    explanation: {
                        type: SchemaType.STRING,
                        description: "A clear explanation of why deleting this clip would improve the video"
                    },
                    confidence: {
                        type: SchemaType.NUMBER,
                        description: "Confidence score (0-1) in this suggestion"
                    }
                },
                required: ["index", "explanation", "confidence"]
            }
        }]
    },
    {
        functionDeclarations: [{
            name: "moveClip",
            description: "Move a clip from one position to another",
            parameters: {
                type: SchemaType.OBJECT,
                properties: {
                    from: {
                        type: SchemaType.NUMBER,
                        description: "Source index. This is the index of the clip in the currentState.clips array. It is zero-indexed."
                    },
                    to: {
                        type: SchemaType.NUMBER,
                        description: "Destination index. This is the index of the clip in the currentState.clips array. It is zero-indexed."
                    },
                    explanation: {
                        type: SchemaType.STRING,
                        description: "A clear explanation of why moving this clip would improve the video"
                    },
                    confidence: {
                        type: SchemaType.NUMBER,
                        description: "Confidence score (0-1) in this suggestion"
                    }
                },
                required: ["from", "to", "explanation", "confidence"]
            }
        }]
    },
    {
        functionDeclarations: [{
            name: "swapClips",
            description: "Swap a clip with the one next to it",
            parameters: {
                type: SchemaType.OBJECT,
                properties: {
                    index: {
                        type: SchemaType.NUMBER,
                        description: "The index of the clip to swap. This is the index of the clip in the currentState.clips array. It is zero-indexed."
                    },
                    explanation: {
                        type: SchemaType.STRING,
                        description: "A clear explanation of why swapping these clips would improve the video"
                    },
                    confidence: {
                        type: SchemaType.NUMBER,
                        description: "Confidence score (0-1) in this suggestion"
                    }
                },
                required: ["index", "explanation", "confidence"]
            }
        }]
    },
    {
        functionDeclarations: [{
            name: "splitClip",
            description: "Split a clip at a specific time point",
            parameters: {
                type: SchemaType.OBJECT,
                properties: {
                    time: {
                        type: SchemaType.NUMBER,
                        description: "Time position to split at. This is the time in seconds from the start of the video, not the start of the clip."
                    },
                    explanation: {
                        type: SchemaType.STRING,
                        description: "A clear explanation of why splitting the clip at this point would improve the video"
                    },
                    confidence: {
                        type: SchemaType.NUMBER,
                        description: "Confidence score (0-1) in this suggestion"
                    }
                },
                required: ["time", "explanation", "confidence"]
            }
        }]
    },
    {
        functionDeclarations: [{
            name: "trimClip",
            description: "Trim a clip by adjusting its start and end times",
            parameters: {
                type: SchemaType.OBJECT,
                properties: {
                    clipId: {
                        type: SchemaType.STRING,
                        description: "ID of the clip to modify (string representation of numeric ID)"
                    },
                    startTime: {
                        type: SchemaType.NUMBER,
                        description: "New start time"
                    },
                    endTime: {
                        type: SchemaType.NUMBER,
                        description: "New end time"
                    },
                    explanation: {
                        type: SchemaType.STRING,
                        description: "A clear explanation of why trimming this clip would improve the video"
                    },
                    confidence: {
                        type: SchemaType.NUMBER,
                        description: "Confidence score (0-1) in this suggestion"
                    }
                },
                required: ["clipId", "startTime", "endTime", "explanation", "confidence"]
            }
        }]
    },
    {
        functionDeclarations: [{
            name: "updateVolume",
            description: "Update the volume of a clip",
            parameters: {
                type: SchemaType.OBJECT,
                properties: {
                    clipId: {
                        type: SchemaType.STRING,
                        description: "ID of the clip to modify (string representation of numeric ID)"
                    },
                    volume: {
                        type: SchemaType.NUMBER,
                        description: "New volume level (0-1)"
                    },
                    explanation: {
                        type: SchemaType.STRING,
                        description: "A clear explanation of why adjusting the volume would improve the video"
                    },
                    confidence: {
                        type: SchemaType.NUMBER,
                        description: "Confidence score (0-1) in this suggestion"
                    }
                },
                required: ["clipId", "volume", "explanation", "confidence"]
            }
        }]
    },
    {
        functionDeclarations: [{
            name: "updateZoom",
            description: "Update the zoom configuration of a clip",
            parameters: {
                type: SchemaType.OBJECT,
                properties: {
                    clipId: {
                        type: SchemaType.STRING,
                        description: "ID of the clip to modify (string representation of numeric ID)"
                    },
                    config: {
                        type: SchemaType.OBJECT,
                        description: "Zoom configuration",
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
                    },
                    explanation: {
                        type: SchemaType.STRING,
                        description: "A clear explanation of why this zoom configuration would improve the video"
                    },
                    confidence: {
                        type: SchemaType.NUMBER,
                        description: "Confidence score (0-1) in this suggestion"
                    }
                },
                required: ["clipId", "config", "explanation", "confidence"]
            }
        }]
    }
];

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
const generateErrorFeedbackPrompt = (originalPrompt: string, error: Error, functionName?: EditFunctionName): string => {
    const functionGuidance = functionName ? `
You attempted to use the "${functionName}" function but it failed. Here are the requirements for this function:
${geminiEditFunctions.find(f => (f as any).functionDeclarations?.[0]?.name === functionName)
            ? Object.entries((geminiEditFunctions.find(f => (f as any).functionDeclarations?.[0]?.name === functionName) as any).functionDeclarations[0].parameters.properties)
                .map(([key, value]) => `- ${key}: ${(value as any).description}`).join("\n")
            : "Function not found"}`
        : `
Available functions:
${geminiEditFunctions.map(f => `- ${(f as any).functionDeclarations[0].name}: ${(f as any).functionDeclarations[0].description}`).join("\n")}`;

    return `${originalPrompt}

PREVIOUS ATTEMPT FAILED WITH ERROR:
The previous suggestion was invalid because: ${error.message}

${functionGuidance}

Please provide a new suggestion using one of the available functions. Pay special attention to:
1. Choosing the most appropriate function for your suggestion
2. Including all required fields for the chosen function
3. Using the correct data types for all fields
4. Ensuring numeric values are valid and within bounds
5. Including a clear explanation and confidence score`;
};

// Add type for function names
type EditFunctionName =
    | "deleteClip"
    | "moveClip"
    | "swapClips"
    | "splitClip"
    | "trimClip"
    | "updateVolume"
    | "updateZoom";

// Add type for raw function responses
type RawFunctionResponse = {
    explanation: string;
    confidence: number;
} & (
        | { index: number } // deleteClip, swapClips
        | { from: number; to: number } // moveClip
        | { time: number } // splitClip
        | { clipId: string; startTime: number; endTime: number } // trimClip
        | { clipId: string; volume: number } // updateVolume
        | { clipId: string; config: z.infer<typeof ZoomConfigSchema> } // updateZoom
    );

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
            let lastGeminiResponse: any = null;

            while (attempts < MAX_RETRIES) {
                try {
                    console.log(`Attempt ${attempts + 1} of ${MAX_RETRIES}`);

                    // Get response from Gemini
                    const result = await model.generateContent({
                        contents: [{ role: "user", parts: [{ text: currentPrompt }] }],
                        generationConfig,
                        safetySettings,
                        tools: geminiEditFunctions
                    });

                    const geminiResponse = await result.response;
                    lastGeminiResponse = geminiResponse;
                    console.log("Full Gemini response:", JSON.stringify(geminiResponse, null, 2));

                    const functionCall = geminiResponse.candidates?.[0]?.content?.parts?.[0]?.functionCall;
                    console.log("Function call data:", JSON.stringify(functionCall, null, 2));

                    if (!functionCall) {
                        throw new Error("No valid edit suggestion received");
                    }

                    // Parse and validate the suggestion
                    console.log("Raw function args:", typeof functionCall.args, functionCall.args);
                    const suggestion = typeof functionCall.args === "string"
                        ? JSON.parse(functionCall.args)
                        : functionCall.args;
                    console.log("Parsed suggestion:", JSON.stringify(suggestion, null, 2));

                    const rawResponse = suggestion as RawFunctionResponse;
                    const functionName = functionCall.name as EditFunctionName;

                    // Convert the function call to our EditSuggestion format
                    const editSuggestion: EditSuggestion = {
                        action: {
                            type: functionName,
                            ...Object.fromEntries(
                                Object.entries(rawResponse).filter(
                                    ([key]) => !["explanation", "confidence"].includes(key)
                                )
                            )
                        } as any, // Safe to use 'as any' here since we validate with Zod schema right after
                        explanation: rawResponse.explanation,
                        confidence: Number(rawResponse.confidence)
                    };

                    const validatedSuggestion = EditSuggestionSchema.parse(editSuggestion);

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
                    const lastFunctionCall = lastGeminiResponse?.candidates?.[0]?.content?.parts?.[0]?.functionCall;
                    currentPrompt = generateErrorFeedbackPrompt(
                        generatePrompt(data),
                        error instanceof Error ? error : new Error(String(error)),
                        lastFunctionCall?.name as EditFunctionName
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