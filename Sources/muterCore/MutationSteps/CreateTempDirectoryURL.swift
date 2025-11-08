import Foundation

struct CreateMutatedProjectDirectoryURL: MutationStep {
    func run(
        with state: AnyMutationTestState
    ) async throws -> [MutationTestState.Change] {
        let destinationPath = destinationPath(
            with: state.projectDirectoryURL
        )

        return [
            .tempDirectoryUrlCreated(URL(fileURLWithPath: destinationPath))
        ]
    }

    private func destinationPath(
        with projectDirectoryURL: URL
    ) -> String {
        let lastComponent = projectDirectoryURL.lastPathComponent
        let mutatedName = lastComponent + "_mutated"

        if let override = ProcessInfo.processInfo.environment["MUTER_MUTATED_ROOT"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = NSString(string: override).expandingTildeInPath
            let rootURL = URL(fileURLWithPath: expanded, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
                return rootURL.appendingPathComponent(mutatedName).path
            } catch {
                // Fall back to default location below
            }
        }

        let modifiedDirectory = projectDirectoryURL.deletingLastPathComponent()
        let destination = modifiedDirectory.appendingPathComponent(mutatedName)
        return destination.path
    }
}
