import * as functions from "firebase-functions";
import { z } from "zod";
import {
    GoogleGenerativeAI,
    HarmCategory,
    HarmBlockThreshold,
    SafetySetting,
    Tool,
    SchemaType
} from "@google/generative-ai";

// Initialize Gemini
const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || "");
const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

// Zod schemas for our types
const ZoomConfigSchema = z.object({
    startZoomIn: z.number(),
    zoomInComplete: z.number().optional(),
    startZoomOut: z.number().optional(),
    zoomOutComplete: z.number().optional()
});

const VideoClipStateSchema = z.object({
    id: z.number(),
    startTime: z.number(),
    endTime: z.number(),
    zoomConfig: ZoomConfigSchema.optional()
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
    confidence: z.number().min(0).max(1),
    impact: z.object({
        pacing: z.number().min(0).max(1).optional(),
        engagement: z.number().min(0).max(1).optional(),
        quality: z.number().min(0).max(1).optional()
    })
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

interface EditSuggestionResponse {
    suggestions: EditSuggestion[];
}

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
                            description: "The index of the clip to modify (for deleteClip, swapClips)"
                        },
                        from: {
                            type: SchemaType.NUMBER,
                            description: "Source index for moveClip"
                        },
                        to: {
                            type: SchemaType.NUMBER,
                            description: "Destination index for moveClip"
                        },
                        time: {
                            type: SchemaType.NUMBER,
                            description: "Time position for splitClip"
                        },
                        clipId: {
                            type: SchemaType.NUMBER,
                            description: "ID of the clip to modify (for trimClip, updateVolume, updateZoom)"
                        },
                        startTime: {
                            type: SchemaType.NUMBER,
                            description: "New start time for trimClip"
                        },
                        endTime: {
                            type: SchemaType.NUMBER,
                            description: "New end time for trimClip"
                        },
                        volume: {
                            type: SchemaType.NUMBER,
                            description: "New volume level (0-1) for updateVolume"
                        },
                        config: {
                            type: SchemaType.OBJECT,
                            description: "Zoom configuration for updateZoom",
                            properties: {
                                startZoomIn: { type: SchemaType.NUMBER },
                                zoomInComplete: { type: SchemaType.NUMBER },
                                startZoomOut: { type: SchemaType.NUMBER },
                                zoomOutComplete: { type: SchemaType.NUMBER }
                            }
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
                },
                impact: {
                    type: SchemaType.OBJECT,
                    description: "Expected impact scores for different aspects of the video",
                    properties: {
                        pacing: {
                            type: SchemaType.NUMBER,
                            description: "Impact on video pacing (0-1)"
                        },
                        engagement: {
                            type: SchemaType.NUMBER,
                            description: "Impact on viewer engagement (0-1)"
                        },
                        quality: {
                            type: SchemaType.NUMBER,
                            description: "Impact on overall quality (0-1)"
                        }
                    }
                }
            },
            required: ["action", "explanation", "confidence", "impact"]
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

export const suggestEdits = functions.https.onCall(async (request: functions.https.CallableRequest<EditSuggestionRequest>): Promise<EditSuggestionResponse> => {
    const data = request.data;

    try {
        // Validate request using Zod schema
        EditSuggestionRequestSchema.parse(data);

        // Generate the prompt
        const prompt = generatePrompt(data);

        // Get response from Gemini
        const result = await model.generateContent({
            contents: [{ role: "user", parts: [{ text: prompt }] }],
            generationConfig,
            safetySettings,
            tools: [geminiEditFunction]
        });

        const response = await result.response;
        const functionCall = response.candidates?.[0]?.content?.parts?.[0]?.functionCall;

        if (!functionCall || functionCall.name !== "suggestEdit") {
            throw new Error("No valid edit suggestion received");
        }

        // Parse and validate the suggestion
        const suggestion = JSON.parse(functionCall.args.toString());
        const validatedSuggestion = EditSuggestionSchema.parse(suggestion);

        return {
            suggestions: [validatedSuggestion]
        };

    } catch (error) {
        console.error("Error generating suggestion:", error);
        throw new functions.https.HttpsError(
            "internal",
            "Error generating edit suggestion",
            error
        );
    }
}); 