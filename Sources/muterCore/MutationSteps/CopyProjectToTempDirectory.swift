import Foundation

class CopyProjectToTempDirectory: MutationStep {
    @Dependency(\.fileManager)
    private var fileManager: FileSystemManager
    @Dependency(\.notificationCenter)
    private var notificationCenter: NotificationCenter

    func run(
        with state: AnyMutationTestState
    ) async throws -> [MutationTestState.Change] {
        do {
            notificationCenter.post(
                name: .projectCopyStarted,
                object: nil
            )

            try fileManager.copyItem(
                atPath: state.projectDirectoryURL.path,
                toPath: state.mutatedProjectDirectoryURL.path
            )

            removeBuildArtifacts(in: state.mutatedProjectDirectoryURL)
            resolvePackageDependencies(in: state.mutatedProjectDirectoryURL)
            applySwiftBox2DCasefoldPatch(in: state.mutatedProjectDirectoryURL)
            prepareAudioFluxRuntime(in: state.mutatedProjectDirectoryURL)

            notificationCenter.post(
                name: .projectCopyFinished,
                object: state.mutatedProjectDirectoryURL.path
            )

            return []
        } catch {
            throw MuterError.projectCopyFailed(
                reason: error.localizedDescription
            )
        }
    }

    private func removeBuildArtifacts(in directoryURL: URL) {
        let pathsToPrune = [
            ".build",
            "Derived",
            "DerivedData"
        ]

        for relativePath in pathsToPrune {
            let targetURL = directoryURL.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.removeItem(atPath: targetURL.path)
            }
        }
    }

    private func resolvePackageDependencies(in directoryURL: URL) {
        let process = MuterProcessFactory.makeProcess()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let escapedPath = directoryURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        process.arguments = [
            "bash",
            "-lc",
            "cd \"\(escapedPath)\" && swift package resolve --skip-update"
        ]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Not fatal; dependency resolution will be retried when tests run.
        }
    }

    private func applySwiftBox2DCasefoldPatch(in directoryURL: URL) {
        let scriptURL = directoryURL
            .appendingPathComponent("Tools")
            .appendingPathComponent("scripts")
            .appendingPathComponent("fix-swiftbox2d-casefold.sh")

        guard fileManager.fileExists(atPath: scriptURL.path) else { return }

        let process = MuterProcessFactory.makeProcess()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let escapedPath = directoryURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        process.arguments = [
            "bash",
            "-lc",
            "cd \"\(escapedPath)\" && Tools/scripts/fix-swiftbox2d-casefold.sh"
        ]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Non-fatal: if the script is missing dependencies or fails, keep going.
        }
    }

    private func prepareAudioFluxRuntime(in directoryURL: URL) {
        let libRoot = directoryURL
            .appendingPathComponent("ThirdParty")
            .appendingPathComponent("CXX")
            .appendingPathComponent("audioFlux")
            .appendingPathComponent("build")
            .appendingPathComponent("macOSBuild")

        let dylibURL = libRoot.appendingPathComponent("libaudioflux.dylib")
        guard fileManager.fileExists(atPath: dylibURL.path) else { return }

        let buildLibDir = directoryURL
            .appendingPathComponent(".build")
            .appendingPathComponent("arm64-apple-macosx")
            .appendingPathComponent("debug")

        try? fileManager.createDirectory(
            atPath: buildLibDir.path,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let symlinkPath = buildLibDir.appendingPathComponent("libaudioflux.dylib").path
        if fileManager.fileExists(atPath: symlinkPath) {
            try? fileManager.removeItem(atPath: symlinkPath)
        }
        try? FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: dylibURL.path)
    }
}
