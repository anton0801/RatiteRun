//
//  MotionManager.swift
//  RatiteRun
//
//  Lightweight CoreMotion wrapper for onboarding parallax (degrades on sim).
//

import Foundation
import CoreMotion
import SwiftUI

final class MotionManager: ObservableObject {
    @Published var roll: Double = 0
    @Published var pitch: Double = 0

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self = self, let m = motion else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                self.roll = m.attitude.roll
                self.pitch = m.attitude.pitch
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        roll = 0; pitch = 0
    }
}
