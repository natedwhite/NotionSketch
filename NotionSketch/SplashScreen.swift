import SwiftUI

/// Branded splash screen shown while the app initializes.
struct SplashScreen: View {

    @State private var progress: CGFloat = 0.0

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // App icon
                Image("AppIconDisplay")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)

                Text("NotionSketch")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                // Progress Bar
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 200, height: 4)
                    
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: progress * 200, height: 4)
                }
                .padding(.top, 8)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    progress = 1.0
                }
            }
            // Matches LaunchScreen constraint: Image center is -50 from view center.
            // Since Image is 100px, top half is 50px.
            // VStack centers itself. To approximate the LaunchScreen layout:
            // LaunchScreen: Image Center Y = View Center Y - 50.
            //               Label Top = Image Bottom + 24.
            //               Label Height ~27.
            // Visual Center of this block is roughly: (Image(100) + Spacing(24) + Label(27)) / 2 = 75.5 from top.
            // Image center is at 50 from top.
            // So we need to shift this block so the image center lands at -50.
            // Shift = -50 + (75.5 - 50) = -24.5 ??
            // Let's just center it naturally; exact pixel match is hard across devices without GeometryReader.
            // A slight shift up looks better optically anyway.
            .offset(y: -20)
        }
    }
}

#Preview {
    SplashScreen()
}
