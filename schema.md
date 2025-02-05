erDiagram
    User {
        string id PK
        string email
        string displayName
        timestamp createdAt
        timestamp updatedAt
    }

    Video {
        string id PK
        enum type "exercise|workout|workoutPlan"
        string title
        string description
        string instructorId FK
        string videoUrl
        string thumbnailUrl
        enum difficulty "beginner|intermediate|advanced"
        array targetMuscles
        timestamp createdAt
        timestamp updatedAt
    }

    Like {
        string id PK
        string videoId FK
        string userId FK
        timestamp createdAt
    }

    Exercise {
        string id PK "extends Video"
        int duration "in seconds"
        int sets "optional"
        int reps "optional"
    }

    Workout {
        string id PK "extends Video"
        array exercises "array of Exercise objects with matching IDs"
        timestamp estimatedDuration "optional"
    }

    WorkoutPlan {
        string id PK "extends Video"
        array workouts "array of {workout: Workout object with matching ID, weekNumber: int, dayOfWeek: int (1-7)}"
        int duration "in days"
    }

    Comment {
        string id PK
        string videoId FK
        string userId FK
        string content
        timestamp createdAt
        timestamp updatedAt
    }

    ExerciseCompletion {
        string id PK
        string exerciseId FK
        string userId FK
        int repsCompleted
        float weight "optional, in lbs"
        string notes "optional"
        timestamp completedAt
    }

    WorkoutCompletion {
        string id PK
        string workoutId FK
        string userId FK
        array exerciseCompletions "exerciseCompletionIds"
        timestamp startedAt
        timestamp finishedAt
        string notes "optional"
    }

    WorkoutPlanProgress {
        string id PK
        string workoutPlanId FK
        string userId FK
        array workoutCompletions "workoutCompletionIds"
        int currentDay
        boolean isCompleted
        timestamp startedAt
        timestamp completedAt "optional"
    }

    User ||--o{ Video : creates
    User ||--o{ Comment : writes
    User ||--o{ Like : gives
    User ||--o{ ExerciseCompletion : completes
    User ||--o{ WorkoutCompletion : completes
    User ||--o{ WorkoutPlanProgress : follows
    Video ||--o{ Comment : has
    Video ||--o{ Like : receives
    Exercise ||--o{ ExerciseCompletion : tracked_by
    Workout ||--o{ WorkoutCompletion : tracked_by
    WorkoutPlan ||--o{ WorkoutPlanProgress : tracked_by