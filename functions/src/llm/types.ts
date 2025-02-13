import { z } from "zod";

// Zod schemas for our types
export const ZoomConfigSchema = z.object({
    startZoomIn: z.number(),
    zoomInComplete: z.number().optional(),
    startZoomOut: z.number().optional(),
    zoomOutComplete: z.number().optional(),
    focusedJoint: z.string().optional()
});

export const DetectedSetSchema = z.object({
    reps: z.number(),
    startTime: z.number(),
    endTime: z.number(),
    keyJoint: z.string()
});

export const VideoClipStateSchema = z.object({
    id: z.number(),
    startTime: z.number(),
    endTime: z.number(),
    zoomConfig: ZoomConfigSchema.optional(),
    detectedSets: z.array(DetectedSetSchema).optional()
});

export const EditorStateSchema = z.object({
    clips: z.array(VideoClipStateSchema),
    selectedClipIndex: z.number().optional()
});

// Define the edit action schemas
export const SuggestedEditActionSchema = z.discriminatedUnion("type", [
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

export const EditActionSchema = z.discriminatedUnion("type", [
    z.object({
        type: z.literal("addClip"),
        clipId: z.string()
    }),
    ...SuggestedEditActionSchema.options
]);

export const EditSuggestionSchema = z.object({
    action: SuggestedEditActionSchema,
    explanation: z.string(),
    confidence: z.number().min(0).max(1)
});

export const EditHistoryEntrySchema = z.object({
    id: z.string(),
    title: z.string(),
    timestamp: z.number().transform((timestamp) => new Date(timestamp)),
    action: EditActionSchema,
    isApplied: z.boolean()
});

export const EditSuggestionRequestSchema = z.object({
    prompt: z.string(),
    currentState: EditorStateSchema,
    editHistory: z.array(EditHistoryEntrySchema),
    provider: z.enum(["gemini", "groq"]).optional()
});

// Export inferred types
export type EditSuggestionRequest = z.infer<typeof EditSuggestionRequestSchema>;
export type EditSuggestion = z.infer<typeof EditSuggestionSchema>;
export type EditFunctionName =
    | "deleteClip"
    | "moveClip"
    | "swapClips"
    | "splitClip"
    | "trimClip"
    | "updateVolume"
    | "updateZoom";

// Common interface for LLM providers
export interface LLMProvider {
    generateSuggestion(prompt: string): Promise<{
        functionCall?: {
            name: string;
            args: any;
        };
    }>;
}

// Type for raw function responses
export type RawFunctionResponse = {
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