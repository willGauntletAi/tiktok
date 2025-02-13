import Groq from "groq-sdk";
import { Tool, SchemaType } from "@google/generative-ai";
import { LLMProvider } from "./types";
import { editFunctions } from "./functions";

// Type for converting Gemini Tool to Groq format
type GroqFunction = {
    name: string;
    description: string;
    parameters: {
        type: string;
        properties: Record<string, any>;
        required: string[];
    };
};

// Convert Gemini function format to Groq format
function convertToGroqFunction(tool: Tool): GroqFunction {
    const decl = (tool as any).functionDeclarations[0];
    return {
        name: decl.name,
        description: decl.description,
        parameters: {
            type: "object",
            properties: Object.fromEntries(
                Object.entries(decl.parameters.properties).map(([key, value]: [string, any]) => [
                    key,
                    {
                        type: value.type === SchemaType.NUMBER ? "number" :
                            value.type === SchemaType.STRING ? "string" :
                                value.type === SchemaType.OBJECT ? "object" : "string",
                        description: value.description,
                        ...(value.enum ? { enum: value.enum } : {}),
                        ...(value.properties ? {
                            properties: value.properties,
                            required: value.required || []
                        } : {})
                    }
                ])
            ),
            required: decl.parameters.required || []
        }
    };
}

export class GroqProvider implements LLMProvider {
    private client: Groq;
    private readonly GROQ_SYSTEM_PROMPT = `You are an expert video editor AI assistant. Your task is to suggest specific edits to improve videos.
You have access to several functions for different types of edits. Always choose the most appropriate function for the task.
Your suggestions should consider:
1. Pacing and flow between clips
2. Engagement and visual interest
3. Overall quality and polish
4. Exercise set timing and transitions

When working with exercise clips:
- Look for opportunities to trim dead time
- Consider strategic zoom effects
- Keep exercise sets intact
- Align transitions with natural movement boundaries

Always provide:
- A specific, actionable edit using one of the available functions
- A clear explanation of the improvement
- A confidence score (0-1) based on how certain you are about the suggestion`;

    constructor(apiKey: string) {
        this.client = new Groq({
            apiKey: apiKey
        });
    }

    async generateSuggestion(prompt: string) {
        const completion = await this.client.chat.completions.create({
            messages: [
                { role: "system", content: this.GROQ_SYSTEM_PROMPT },
                { role: "user", content: prompt }
            ],
            model: "mixtral-8x7b-32768",
            temperature: 0.7,
            functions: editFunctions.map(convertToGroqFunction),
            function_call: { name: "auto" }
        });

        const functionCall = completion.choices[0]?.message?.function_call;

        if (!functionCall) {
            throw new Error("No valid edit suggestion received from Groq");
        }

        return {
            functionCall: {
                name: functionCall.name,
                args: JSON.parse(functionCall.arguments)
            }
        };
    }
} 