//
//  LaunchAnimationView.swift
//  CoupleSpace
//

import SwiftUI

struct LaunchAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var phase = 0

    var body: some View {
        ZStack {
            LaunchPalette.oatWhite
                .ignoresSafeArea()

            VStack(spacing: 34) {
                ZStack {
                    RoundedRectangle(cornerRadius: 35, style: .continuous)
                        .fill(LaunchPalette.indigo)
                        .frame(width: 112, height: 150)
                        .offset(x: phase >= 2 ? -11 : -29)

                    RoundedRectangle(cornerRadius: 35, style: .continuous)
                        .fill(LaunchPalette.coral)
                        .frame(width: 112, height: 150)
                        .offset(x: phase >= 2 ? 11 : 29)

                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(LaunchPalette.window)
                        .frame(width: 70, height: 64)
                        .shadow(
                            color: LaunchPalette.amber.opacity(phase >= 3 ? 0.45 : 0),
                            radius: 16
                        )
                        .scaleEffect(phase >= 3 ? 1 : 0.72)
                        .opacity(phase >= 3 ? 1 : 0)
                        .overlay {
                            HStack(spacing: 18) {
                                eye
                                eye
                            }
                            .opacity(phase >= 4 ? 1 : 0)
                        }

                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LaunchPalette.window)
                        .frame(width: 24, height: 24)
                        .shadow(color: LaunchPalette.amber.opacity(0.4), radius: 8)
                        .offset(y: phase >= 4 ? -102 : -91)
                        .opacity(phase >= 4 ? 1 : 0)
                }
                .opacity(phase >= 1 ? 1 : 0)
                .scaleEffect(phase >= 1 ? 1 : 0.94)
                .rotationEffect(.degrees(phase >= 4 ? 2 : 0))

                Text("Moment")
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(LaunchPalette.indigo)
                    .opacity(phase >= 5 ? 1 : 0)
                    .offset(y: phase >= 5 ? 0 : 8)
            }
            .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
        .task {
            await play()
        }
    }

    private var eye: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(LaunchPalette.indigo.opacity(0.88))
            .frame(width: 8, height: 12)
    }

    private func play() async {
        if reduceMotion {
            guard await pause(milliseconds: 150) else { return }
            onFinished()
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            phase = 1
        }
        guard await pause(milliseconds: 200) else { return }

        withAnimation(.easeInOut(duration: 0.30)) {
            phase = 2
        }
        guard await pause(milliseconds: 300) else { return }

        withAnimation(.easeOut(duration: 0.22)) {
            phase = 3
        }
        guard await pause(milliseconds: 220) else { return }

        withAnimation(.spring(duration: 0.20, bounce: 0.16)) {
            phase = 4
        }
        guard await pause(milliseconds: 200) else { return }

        withAnimation(.easeOut(duration: 0.20)) {
            phase = 5
        }
        guard await pause(milliseconds: 360) else { return }

        onFinished()
    }

    private func pause(milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return true
        } catch {
            return false
        }
    }
}

private enum LaunchPalette {
    // Provisional approximations until the brand color tokens are finalized.
    static let indigo = Color(red: 0.20, green: 0.14, blue: 0.27)
    static let coral = Color(red: 0.91, green: 0.43, blue: 0.35)
    static let oatWhite = Color(red: 0.976, green: 0.957, blue: 0.929)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.31)
    static let window = Color(red: 1.0, green: 0.89, blue: 0.62)
}

#Preview {
    LaunchAnimationView(onFinished: {})
}
