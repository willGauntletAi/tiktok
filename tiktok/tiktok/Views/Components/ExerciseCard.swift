import SwiftUI

struct ExerciseCard: View {
  let exercise: Exercise
  
  var body: some View {
    VStack(alignment: .leading) {
      AsyncImage(url: URL(string: exercise.thumbnailUrl)) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        Rectangle()
          .fill(Color.gray.opacity(0.2))
      }
      .frame(height: 200)
      .cornerRadius(10)
      
      VStack(alignment: .leading, spacing: 4) {
        Text(exercise.title)
          .font(.headline)
        
        Text(exercise.description)
          .font(.subheadline)
          .foregroundColor(.secondary)
          .lineLimit(2)
        
        HStack {
          Text(exercise.difficulty.rawValue.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(8)
          
          ForEach(exercise.targetMuscles.prefix(3), id: \.self) { muscle in
            Text(muscle)
              .font(.caption)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.green.opacity(0.2))
              .cornerRadius(8)
          }
          
          if exercise.targetMuscles.count > 3 {
            Text("+\(exercise.targetMuscles.count - 3)")
              .font(.caption)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.green.opacity(0.2))
              .cornerRadius(8)
          }
        }
      }
      .padding(.vertical, 8)
    }
    .background(Color(.systemBackground))
    .cornerRadius(12)
    .shadow(radius: 2)
  }
} 