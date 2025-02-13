import { EditSuggestionRequest, EditFunctionName } from "./types";
import { editFunctions } from "./functions";

export const generatePrompt = (request: EditSuggestionRequest): string => {
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
- Ensure transitions align with natural exercise boundaries`;
};

export const generateErrorFeedbackPrompt = (originalPrompt: string, error: Error, functionName?: EditFunctionName): string => {
    const functionGuidance = functionName ? `
You attempted to use the "${functionName}" function but it failed. Here are the requirements for this function:
${editFunctions.find(f => (f as any).functionDeclarations?.[0]?.name === functionName)
            ? Object.entries((editFunctions.find(f => (f as any).functionDeclarations?.[0]?.name === functionName) as any).functionDeclarations[0].parameters.properties)
                .map(([key, value]) => `- ${key}: ${(value as any).description}`).join("\n")
            : "Function not found"}`
        : `
Available functions:
${editFunctions.map(f => `- ${(f as any).functionDeclarations[0].name}: ${(f as any).functionDeclarations[0].description}`).join("\n")}`;

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