import Foundation

@MainActor
final class Runner: ObservableObject {

    @Published private(set) var pace: Pace = .rest
    @Published private(set) var offline = false

    private var stride = Stride()
    private var settled = false
    private var busy = false
    private var live = false
    private var clock: Task<Void, Never>?

    func ignite() {
        prime()
        clock = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.stop()
        }
        roll()
    }

    func feed(_ pour: [String: String]) {
        prime()
        stride.raw.merge(pour) { _, fresh in fresh }
        Nest.write(stride)
        roll()
    }

    func pair(_ pour: [String: String]) {
        prime()
        for (key, value) in pour where stride.links[key] == nil { stride.links[key] = value }
        Nest.write(stride)
    }

    func nod() {
        prime()
        Task { [weak self] in
            guard let self = self else { return }
            let granted = await Beak.peck()
            self.stride.consentGrant = granted
            self.stride.consentDeny = !granted
            self.stride.consentAt = Date()
            Nest.write(self.stride)
            self.pace = .run
        }
    }

    func veer() {
        prime()
        stride.consentAt = Date()
        Nest.write(stride)
        pace = .run
    }

    func power(_ up: Bool) {
        if !up { offline = true }
    }

    private func roll() {
        guard !settled, !busy else { return }

        if let hot = pending {
            pin(hot)
            return
        }
        guard stride.rolling else { return }

        busy = true
        Task { [weak self] in
            guard let self = self else { return }

            if self.stride.needsWarmup {
                self.stride.refetched = true
                Nest.write(self.stride)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let fresh = await Sprint.probe()
                if !fresh.isEmpty {
                    var pooled = fresh
                    for (key, value) in self.stride.links where pooled[key] == nil { pooled[key] = value }
                    self.stride.raw = pooled
                    Nest.write(self.stride)
                }
            }

            let sight = await Sprint.send(self.stride.raw)
            self.busy = false
            switch sight {
            case .fixed(let url): self.pin(url)
            case .blank: self.stop()
            }
        }
    }

    private func pin(_ url: String) {
        guard latch() else { return }
        let ask = stride.askable
        stride.routeURL = url
        stride.routeMode = "Active"
        stride.virgin = false
        Nest.write(stride)
        Nest.mark(url)
        Nest.flag()
        UserDefaults.standard.removeObject(forKey: Peck.pushURL)
        pace = ask ? .prompt : .run
    }

    private func stop() {
        guard latch() else { return }
        pace = .halt
    }

    private func latch() -> Bool {
        guard !settled else { return false }
        settled = true
        clock?.cancel()
        return true
    }

    private func prime() {
        guard !live else { return }
        live = true
        stride = Nest.read()
    }

    private var pending: String? {
        let value = UserDefaults.standard.string(forKey: Peck.pushURL) ?? ""
        return value.isEmpty ? nil : value
    }
}
