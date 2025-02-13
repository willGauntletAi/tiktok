import * as functions from "firebase-functions";
import { onCall } from "firebase-functions/v2/https";
import type {
    EditSuggestion,
    EditFunctionName,
    RawFunctionResponse
} from "./llm";
import {
    EditSuggestionRequestSchema,
    EditSuggestionSchema,
    LLMProviderFactory
} from "./llm";
import { generatePrompt, generateErrorFeedbackPrompt } from "./llm/prompts";

// Add max retries constant
const MAX_RETRIES = 3;

interface LLMResponse {
    functionCall?: {
        name: string;
        args: Record<string, unknown>;
    };
}

export const suggestEdits = onCall(
    {
        timeoutSeconds: 120,
        memory: "256MiB"
    },
    async (request): Promise<{ suggestions: EditSuggestion[] }> => {
        const data = request.data;
        const providerType = data.provider || "gemini"; // Default to Gemini if not specified
        const llmProvider = LLMProviderFactory.createProvider(providerType as "gemini" | "groq");

        try {
            // Validate request using Zod schema
            EditSuggestionRequestSchema.parse(data);

            // Generate initial prompt
            let currentPrompt = generatePrompt(data);
            let attempts = 0;
            let lastResponse: LLMResponse | null = null;

            while (attempts < MAX_RETRIES) {
                try {
                    console.log(`Attempt ${attempts + 1} of ${MAX_RETRIES}`);

                    // Get response from LLM provider
                    const response = await llmProvider.generateSuggestion(currentPrompt);
                    lastResponse = response;
                    console.log("LLM response:", JSON.stringify(response, null, 2));

                    const { functionCall } = response;
                    if (!functionCall) {
                        throw new Error("No valid edit suggestion received");
                    }

                    const rawResponse = functionCall.args as RawFunctionResponse;
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
                        } as any, // This any is needed due to the dynamic nature of the action type
                        explanation: rawResponse.explanation,
                        confidence: Number(rawResponse.confidence)
                    };

                    const validatedSuggestion = EditSuggestionSchema.parse(editSuggestion);

                    return {
                        suggestions: [validatedSuggestion]
                    };

                } catch (error) {
                    attempts++;
                    console.log(`Attempt ${attempts} failed:`, error);

                    if (attempts >= MAX_RETRIES) {
                        throw error;
                    }

                    // Update prompt with error feedback for next attempt
                    const lastFunctionCall = lastResponse?.functionCall;
                    currentPrompt = generateErrorFeedbackPrompt(
                        generatePrompt(data),
                        error instanceof Error ? error : new Error(String(error)),
                        lastFunctionCall?.name as EditFunctionName
                    );
                }
            }

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