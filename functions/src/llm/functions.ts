import { Tool, SchemaType } from "@google/generative-ai";

// Function schemas for LLMs
export const editFunctions: Tool[] = [
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