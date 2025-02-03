```mermaid
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
        array exercises "exerciseIds with order"
        int totalDuration "in seconds"
    }

    WorkoutPlan {
        string id PK "extends Video"
        array workouts "workoutIds with order"
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

    User ||--o{ Video : creates
    User ||--o{ Comment : writes
    User ||--o{ Like : gives
    Video ||--o{ Comment : has
    Video ||--o{ Like : receives