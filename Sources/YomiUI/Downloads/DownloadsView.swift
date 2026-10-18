import SwiftUI
import YomiCore
import YomiDownload

public struct DownloadsView: View {
    @State private var downloadManager = DownloadManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if downloadManager.queue.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(YomiTheme.textSecondary)
                        Text("No Active Downloads")
                            .font(.headline)
                        Text("Downloaded chapters will appear here and can be read completely offline.")
                            .font(.subheadline)
                            .foregroundStyle(YomiTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
                    List {
                        Section("Download Queue") {
                            ForEach(downloadManager.queue) { job in
                                DownloadJobRow(job: job)
                            }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #endif
                }
            }
            .navigationTitle("Downloads")
        }
    }
}

struct DownloadJobRow: View {
    let job: DownloadJob
    private let downloadManager = DownloadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.manga.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(job.chapter.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                switch job.status {
                case .queued:
                    Text("Queued")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                case .downloading(let progress, _, _):
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Color.blue)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Text("Failed")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                case .paused:
                    Text("Paused")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                }

                Button {
                    downloadManager.cancel(jobId: job.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if case .downloading(let progress, _, _) = job.status {
                ProgressView(value: progress)
                    .tint(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}
