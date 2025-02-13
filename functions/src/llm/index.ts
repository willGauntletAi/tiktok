import { defineString } from "firebase-functions/params";
import { GeminiProvider } from "./gemini";
import { GroqProvider } from "./groq";
import { LLMProvider } from "./types";

// Define the configuration parameters
const geminiApiKey = defineString("GEMINI_API_KEY");
const groqApiKey = defineString("GROQ_API_KEY");

// Factory for creating LLM providers
export class LLMProviderFactory {
    static createProvider(type: "gemini" | "groq"): LLMProvider {
        switch (type) {
            case "gemini":
                return new GeminiProvider(geminiApiKey.value() || "");
            case "groq":
                return new GroqProvider(groqApiKey.value() || "");
            default:
                throw new Error(`Unsupported LLM provider type: ${type}`);
        }
    }
}

export * from "./types";
export * from "./functions"; 