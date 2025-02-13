import {
    GoogleGenerativeAI,
    HarmCategory,
    HarmBlockThreshold,
    SafetySetting
} from "@google/generative-ai";
import { LLMProvider } from "./types";
import { editFunctions } from "./functions";

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

// Gemini generation config
const generationConfig = {
    temperature: 0.7,
    topK: 40,
    topP: 0.95,
    maxOutputTokens: 1024,
};

export class GeminiProvider implements LLMProvider {
    private model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>;

    constructor(apiKey: string) {
        const genAI = new GoogleGenerativeAI(apiKey);
        this.model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });
    }

    async generateSuggestion(prompt: string) {
        const result = await this.model.generateContent({
            contents: [{ role: "user", parts: [{ text: prompt }] }],
            generationConfig,
            safetySettings,
            tools: editFunctions
        });

        const response = await result.response;
        const functionCall = response.candidates?.[0]?.content?.parts?.[0]?.functionCall;

        if (!functionCall) {
            throw new Error("No valid edit suggestion received from Gemini");
        }

        return {
            functionCall: {
                name: functionCall.name,
                args: typeof functionCall.args === "string" ? JSON.parse(functionCall.args) : functionCall.args
            }
        };
    }
} 