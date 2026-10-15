import SwiftUI

/// Running Docker containers, with graceful states for "not installed" and the
/// (common) "daemon not running".
struct DockerView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var docker: DockerService

    var body: some View {
        switch docker.state {
        case .unavailable:
            FeedStatus(icon: "shippingbox", text: "Docker isn't installed")

        case .notRunning:
            FeedStatus(
                icon: "shippingbox",
                text: "Docker isn't running",
                accessory: AnyView(
                    PillButton(title: "Open Docker", prominent: true) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
                    }
                )
            )

        case .running(let containers):
            if containers.isEmpty {
                FeedStatus(icon: "shippingbox", text: "No running containers")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    SeparatedList(items: containers) { container in
                            ContainerRow(container: container) {
                                state.push(.dockerLogs(name: container.name))
                            }
                            .contextMenu {
                                Button("View Logs") { state.push(.dockerLogs(name: container.name)) }
                                Divider()
                                Button("Restart") { docker.control("restart", container: container.name) }
                                Button("Stop") { docker.control("stop", container: container.name) }
                                Divider()
                                Button("Remove", role: .destructive) { docker.control("rm -f", container: container.name) }
                            }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct ContainerRow: View {
    let container: DockerContainer
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                StatusDot(color: container.isUp ? DS.good : DS.textTertiary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(container.name)
                        .font(.title)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    Text(container.image)
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                Text(container.status)
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Icon("chevron.right", size: 11.7, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
            }
            .rowSurface(hovering: hovering)
        }
        .buttonStyle(Pressable())
        .onHover { h in withAnimation(DS.hover) { hovering = h } }
    }
}
