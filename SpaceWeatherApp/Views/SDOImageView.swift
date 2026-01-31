import SwiftUI

/// Solar image viewer with multi-observatory support
struct SDOImageView: View {
    @Bindable var viewModel: SpaceWeatherViewModel

    // Observatory / measurement selection (owned locally)
    @State private var selectedObservatory: SolarObservatory = .sdo
    @State private var selectedMeasurement: SolarMeasurement = SolarObservatory.sdo.defaultMeasurement

    // Image state
    @State private var isFullScreen = false
    @State private var selectedDate: Date = Date()
    @State private var isLoadingImage = false
    @State private var instrumentImageURL: URL?
    @State private var actualImageDate: Date?
    @State private var dateDebounceTask: Task<Void, Never>?

    // Animation drawer
    @State private var showAnimationDrawer = false

    private let helioviewerService = HelioviewerService()

    var body: some View {
        NavigationStack {
            ZStack {
                DynamicColorBackground(accentColor: selectedMeasurement.color)
                    .animation(.easeInOut(duration: 0.5), value: selectedMeasurement.id)

                ScrollView {
                    VStack(spacing: 16) {
                        observatorySelector
                            .slideIn(from: .top, delay: 0.1)

                        imageSection
                            .scaleFade(delay: 0.15)
                            .onTapGesture {
                                isFullScreen = true
                            }

                        measurementBar
                            .slideIn(from: .leading, delay: 0.2)

                        timeControlsSection
                            .scaleFade(delay: 0.25)

                        animationButton
                            .scaleFade(delay: 0.3)

                        instrumentInfoSection
                            .scaleFade(delay: 0.35)
                    }
                    .padding(.vertical)
                }
                .scrollContentBackground(.hidden)
                .blur(radius: showAnimationDrawer ? 8 : 0)
                .overlay {
                    if showAnimationDrawer {
                        Color.black.opacity(0.3).ignoresSafeArea()
                    }
                }
                .allowsHitTesting(!showAnimationDrawer)

                if showAnimationDrawer {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAnimationDrawer = false
                            }
                        }

                    HStack {
                        Spacer()
                        AnimationDrawer(
                            measurement: selectedMeasurement,
                            observatory: selectedObservatory,
                            helioviewerService: helioviewerService,
                            isPresented: $showAnimationDrawer
                        )
                        .frame(maxWidth: 500)
                        Spacer()
                    }
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SolarTitleView(accentColor: selectedMeasurement.color)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadInstrumentImage() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoadingImage)
                }
            }
            .fullScreenCover(isPresented: $isFullScreen) {
                FullScreenInstrumentView(
                    imageURL: instrumentImageURL,
                    measurement: selectedMeasurement,
                    date: actualImageDate,
                    isPresented: $isFullScreen
                )
            }
        }
        .task {
            viewModel.imageTabAccentColor = selectedMeasurement.color
            await loadInstrumentImage()
        }
        .onChange(of: selectedObservatory) { _, newObservatory in
            let newMeasurement = newObservatory.defaultMeasurement
            selectedMeasurement = newMeasurement
            Task { await loadInstrumentImage() }
        }
        .onChange(of: selectedMeasurement) { _, newMeasurement in
            viewModel.imageTabAccentColor = newMeasurement.color
            Task { await loadInstrumentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            selectedDate = Date()
            Task { await loadInstrumentImage() }
        }
    }

    // MARK: - Observatory Selector

    private var observatorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(SolarObservatory.allCases) { observatory in
                    ObservatoryChip(
                        observatory: observatory,
                        isSelected: selectedObservatory == observatory,
                        accentColor: selectedMeasurement.color
                    ) {
                        withAnimation(Theme.Animation.spring) {
                            selectedObservatory = observatory
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    // MARK: - Image Section

    private var imageSection: some View {
        ZStack {
            if isLoadingImage {
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        VStack(spacing: Theme.Spacing.md) {
                            ProgressView()
                                .scaleEffect(1.4)
                                .tint(selectedMeasurement.color)
                            Text("Loading \(selectedObservatory.displayName)...")
                                .font(Theme.mono(12, weight: .medium))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                    .shimmer()
            } else if let url = instrumentImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                ProgressView()
                                    .scaleEffect(1.4)
                                    .tint(selectedMeasurement.color)
                            }
                            .shimmer()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
                            .shadow(color: selectedMeasurement.color.opacity(0.5), radius: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [selectedMeasurement.color.opacity(0.3), selectedMeasurement.color.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .overlay(alignment: .bottomLeading) {
                                if let date = actualImageDate {
                                    HStack(spacing: 4) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(date.formattedDateTime)
                                            .font(Theme.mono(10, weight: .bold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(12)
                                }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    case .failure:
                        RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                VStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 32))
                                        .foregroundStyle(selectedMeasurement.color.opacity(0.6))
                                    Text("Unable to load image")
                                        .font(Theme.mono(12, weight: .medium))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
                .id(url)
                .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: selectedMeasurement.icon)
                                .font(.system(size: 36))
                                .foregroundStyle(selectedMeasurement.color.opacity(0.6))
                            Text("Tap refresh to load")
                                .font(Theme.mono(12, weight: .medium))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: instrumentImageURL)
        .animation(.easeInOut(duration: 0.3), value: isLoadingImage)
        .padding(.horizontal)
    }

    // MARK: - Measurement Bar

    private var measurementBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedObservatory.measurements) { measurement in
                    MeasurementChip(
                        measurement: measurement,
                        isSelected: selectedMeasurement == measurement
                    ) {
                        withAnimation(Theme.Animation.spring) {
                            selectedMeasurement = measurement
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Time Controls

    private var timeControlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Select Time")
                    .font(Theme.mono(14, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                HStack(spacing: 6) {
                    QuickTimeButton(title: "Now", color: selectedMeasurement.color) {
                        selectedDate = Date()
                        Task { await loadInstrumentImage() }
                    }
                    QuickTimeButton(title: "-3h") {
                        selectedDate = Date().addingTimeInterval(-3 * 3600)
                        Task { await loadInstrumentImage() }
                    }
                    QuickTimeButton(title: "-6h") {
                        selectedDate = Date().addingTimeInterval(-6 * 3600)
                        Task { await loadInstrumentImage() }
                    }
                    QuickTimeButton(title: "-24h") {
                        selectedDate = Date().addingTimeInterval(-24 * 3600)
                        Task { await loadInstrumentImage() }
                    }
                    QuickTimeButton(title: "-48h") {
                        selectedDate = Date().addingTimeInterval(-48 * 3600)
                        Task { await loadInstrumentImage() }
                    }
                }
            }

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(selectedMeasurement.color)
                    Text(selectedDate.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(Theme.mono(14))
                        .foregroundStyle(.white)
                }
                .overlay {
                    DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .colorMultiply(.clear)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundStyle(selectedMeasurement.color)
                    Text(selectedDate.formatted(.dateTime.hour().minute()))
                        .font(Theme.mono(14))
                        .foregroundStyle(.white)
                }
                .overlay {
                    DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .colorMultiply(.clear)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedMeasurement.color.opacity(0.15), lineWidth: 1)
            )
            .onChange(of: selectedDate) { _, _ in
                dateDebounceTask?.cancel()
                dateDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    await loadInstrumentImage()
                }
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Animation Button

    private var animationButton: some View {
        Button {
            withAnimation(Theme.Animation.spring) {
                showAnimationDrawer = true
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(selectedMeasurement.color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(selectedMeasurement.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Animation")
                        .font(Theme.mono(14, weight: .semibold))
                    Text("Generate a timelapse for \(selectedMeasurement.displayName)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.tertiaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.quaternaryText)
            }
            .foregroundStyle(.white)
            .padding(Theme.Spacing.md)
            .background(selectedMeasurement.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(selectedMeasurement.color.opacity(0.2), lineWidth: 1)
            }
        }
        .pressable()
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Instrument Info Section

    private var instrumentInfoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(selectedMeasurement.color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: selectedObservatory.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selectedMeasurement.color)
                }
                Text(selectedMeasurement.fullName)
                    .font(Theme.mono(15, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(selectedMeasurement.description)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.secondaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            Text(selectedObservatory.description)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Helper Methods

    private func loadInstrumentImage() async {
        isLoadingImage = true

        instrumentImageURL = await helioviewerService.getImageURL(
            date: selectedDate,
            measurement: selectedMeasurement,
            width: 1024,
            height: 1024
        )

        // Query the actual closest image date from Helioviewer
        if let closest = try? await helioviewerService.getClosestImage(
            date: selectedDate,
            sourceId: selectedMeasurement.sourceId
        ) {
            actualImageDate = parseHelioviewerDate(closest.date)
        } else {
            actualImageDate = selectedDate
        }

        isLoadingImage = false
    }

    private func parseHelioviewerDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Fallback: try ISO8601
        let iso = ISO8601DateFormatter()
        return iso.date(from: dateString)
    }
}

// MARK: - Observatory Chip

struct ObservatoryChip: View {
    let observatory: SolarObservatory
    let isSelected: Bool
    var accentColor: Color = .orange
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: observatory.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? accentColor : Theme.tertiaryText)
                Text(observatory.displayName)
                    .font(Theme.mono(13, weight: isSelected ? .bold : .medium))
            }
            .foregroundStyle(isSelected ? .white : Theme.secondaryText)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? accentColor.opacity(0.2) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? accentColor.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(Theme.Animation.spring, value: isSelected)
    }
}

// MARK: - Measurement Chip

struct MeasurementChip: View {
    let measurement: SolarMeasurement
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(measurement.color)
                    .frame(width: 10, height: 10)
                    .shadow(color: isSelected ? measurement.color.opacity(0.5) : .clear, radius: 4)
                Text(measurement.displayName)
                    .font(Theme.mono(13, weight: isSelected ? .bold : .medium))
            }
            .foregroundStyle(isSelected ? .white : Theme.secondaryText)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? measurement.color.opacity(0.2) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? measurement.color.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(Theme.Animation.spring, value: isSelected)
    }
}

// MARK: - Supporting Views

struct QuickTimeButton: View {
    let title: String
    var color: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(color != nil ? .white : .white)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(color?.opacity(0.3) ?? Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(color?.opacity(0.4) ?? Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pressable()
    }
}

struct QuickRangeButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full Screen View

struct FullScreenInstrumentView: View {
    let imageURL: URL?
    let measurement: SolarMeasurement
    var date: Date? = nil
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { val in
                                    let delta = val / lastScale
                                    lastScale = val
                                    scale *= delta
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    if scale < 1.0 {
                                        withAnimation {
                                            scale = 1.0
                                            offset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { val in
                                    offset = CGSize(
                                        width: lastOffset.width + val.translation.width,
                                        height: lastOffset.height + val.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    case .failure:
                        ContentUnavailableView("Failed to load image", systemImage: "exclamationmark.triangle")
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(measurement.fullName)
                            .font(Theme.mono(16, weight: .bold))
                            .foregroundStyle(.white)
                        if let date = date {
                            Text(date.formattedDateTime)
                                .font(Theme.mono(12))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
                Spacer()
            }
        }
        .statusBarHidden()
    }
}

#Preview {
    SDOImageView(viewModel: SpaceWeatherViewModel())
}

// MARK: - Animation Bottom Sheet

private struct LoadedFrame: Identifiable {
    let id = UUID()
    let date: Date
    let image: UIImage
}

// MARK: - Animation Drawer

private struct AnimationDrawer: View {
    let measurement: SolarMeasurement
    let observatory: SolarObservatory
    let helioviewerService: HelioviewerService
    @Binding var isPresented: Bool

    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var frameCount: Int = 24
    @State private var didSetDefaults = false

    @State private var isLoading = false
    @State private var loadingProgress: Double = 0
    @State private var loadedFrameCount: Int = 0
    @State private var totalExpectedFrames: Int = 0
    @State private var sparseWarning: String? = nil

    @State private var frames: [LoadedFrame] = []
    @State private var currentFrame: Int = 0
    @State private var isPlaying = false
    @State private var playbackSpeed: Double = 0.15
    @State private var playbackTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?

    private let frameCounts = [12, 24, 48, 72]

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create Animation")
                            .font(Theme.mono(16, weight: .bold))
                            .foregroundStyle(Theme.primaryText)
                        Text(measurement.fullName)
                            .font(Theme.mono(12))
                            .foregroundStyle(measurement.color)
                    }

                    Spacer()

                    Button {
                        stopPlayback()
                        loadTask?.cancel()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.horizontal, 16)
            }

            preview
                .padding(.horizontal, 16)

            if frames.isEmpty && !isLoading {
                config
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                playbackControls
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .frame(width: min(UIScreen.main.bounds.width * 0.95, 450))
        .background(Theme.glassMaterial)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.bottom, 16) // Small space above tab bar
        .padding(.top, 60) // Space for navigation title
        .frame(maxHeight: UIScreen.main.bounds.height * 0.78, alignment: .bottom)
        .onAppear {
            if !didSetDefaults {
                let hours = observatory.suggestedAnimationHours
                endDate = Date()
                startDate = Date().addingTimeInterval(-Double(hours) * 3600)
                didSetDefaults = true
            }
        }
        .onDisappear {
            stopPlayback()
            loadTask?.cancel()
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.3))
                .stroke(Color.white.opacity(0.1), lineWidth: 1)

            if frames.isEmpty && !isLoading {
                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.tertiaryText)
                    Text("Ready to Generate")
                        .font(Theme.mono(14))
                        .foregroundStyle(Theme.secondaryText)
                }
            } else if frames.indices.contains(currentFrame) {
                Image(uiImage: frames[currentFrame].image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(frames[currentFrame].date.formattedDateTime)
                        }
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                        .padding(.bottom, 12)
                    }
            }

            if isLoading {
                VStack {
                    VStack(spacing: 8) {
                        ProgressView(value: loadingProgress)
                            .frame(width: 160)
                            .tint(measurement.color)
                        Text("Loading frame \(loadedFrameCount) of \(totalExpectedFrames)")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(measurement.color)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 20)

                    Spacer()
                }
            }
        }
        .frame(height: min(UIScreen.main.bounds.height * 0.28, 280))
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
    }

    private var config: some View {
        VStack(spacing: 16) {
            // Quick range buttons
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Range")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 4)

                HStack(spacing: 8) {
                    ForEach([(title: "6h", hours: 6), (title: "12h", hours: 12), (title: "24h", hours: 24), (title: "48h", hours: 48), (title: "7d", hours: 168)], id: \.title) { range in
                        Button {
                            endDate = Date()
                            startDate = Date().addingTimeInterval(-Double(range.hours) * 3600)
                        } label: {
                            Text(range.title)
                                .font(Theme.mono(12, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(measurement.color.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(measurement.color.opacity(0.25), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(spacing: 10) {
                datePickerRow(label: "Start", selection: $startDate, range: ...endDate)
                datePickerRow(label: "End", selection: $endDate, range: startDate...Date())
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Frame Count")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 4)

                Picker("Frames", selection: $frameCount) {
                    ForEach(frameCounts, id: \.self) { c in
                        Text("\(c)").tag(c)
                    }
                }
                .pickerStyle(.segmented)
                .onAppear {
                    UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(measurement.color)
                    UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
                    UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.7)], for: .normal)
                }
            }

            Button {
                loadTask?.cancel()
                loadTask = Task { await loadFrames() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.black)
                            .padding(.trailing, 8)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isLoading ? "Generating..." : "Generate Animation")
                        .font(Theme.mono(14, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(measurement.color)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: measurement.color.opacity(0.3), radius: 10, y: 0)
            }
            .disabled(isLoading)
        }
    }

    @ViewBuilder
    private func datePickerRow(label: String, selection: Binding<Date>, range: ClosedRange<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: "calendar")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondaryText)

            HStack {
                Text(selection.wrappedValue.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(Theme.mono(14))
                    .foregroundStyle(.white)
                    .overlay {
                        DatePicker("", selection: selection, in: range, displayedComponents: .date)
                            .labelsHidden()
                            .tint(measurement.color)
                            .colorMultiply(.clear)
                    }

                Spacer()

                Text(selection.wrappedValue.formatted(.dateTime.hour().minute()))
                    .font(Theme.mono(14))
                    .foregroundStyle(.white)
                    .overlay {
                        DatePicker("", selection: selection, in: range, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(measurement.color)
                            .colorMultiply(.clear)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func datePickerRow(label: String, selection: Binding<Date>, range: PartialRangeThrough<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: "calendar")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondaryText)

            HStack {
                Text(selection.wrappedValue.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(Theme.mono(14))
                    .foregroundStyle(.white)
                    .overlay {
                        DatePicker("", selection: selection, in: range, displayedComponents: .date)
                            .labelsHidden()
                            .tint(measurement.color)
                            .colorMultiply(.clear)
                    }

                Spacer()

                Text(selection.wrappedValue.formatted(.dateTime.hour().minute()))
                    .font(Theme.mono(14))
                    .foregroundStyle(.white)
                    .overlay {
                        DatePicker("", selection: selection, in: range, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(measurement.color)
                            .colorMultiply(.clear)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var playbackControls: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                Button {
                    if isPlaying { stopPlayback() } else { startPlayback() }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(measurement.color)
                        .symbolEffect(.bounce, value: isPlaying)
                }

                VStack(spacing: 8) {
                    if frames.count > 1 {
                        Slider(
                            value: Binding(
                                get: { Double(currentFrame) },
                                set: { currentFrame = Int($0) }
                            ),
                            in: 0...Double(frames.count - 1),
                            step: 1
                        )
                        .tint(measurement.color)
                    }

                    HStack {
                        Text("\(currentFrame + 1)/\(frames.count)")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        if isLoading {
                            Text("Loading...")
                                .font(Theme.mono(10))
                                .foregroundStyle(measurement.color.opacity(0.7))
                        }
                        Text("\(Int(1/playbackSpeed)) FPS")
                            .font(Theme.mono(12))
                            .foregroundStyle(measurement.color)
                    }
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            HStack {
                Image(systemName: "hare.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Slider(value: $playbackSpeed, in: 0.05...0.5)
                    .tint(Theme.secondaryText)
                Image(systemName: "tortoise.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)

                Spacer()

                Button("Reset") {
                    stopPlayback()
                    loadTask?.cancel()
                    withAnimation {
                        frames = []
                        currentFrame = 0
                        loadingProgress = 0
                        loadedFrameCount = 0
                        totalExpectedFrames = 0
                        sparseWarning = nil
                        isLoading = false
                    }
                }
                .font(Theme.mono(12))
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.danger.opacity(0.1))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 8)

            if let warning = sparseWarning {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Theme.warning)
                    Text(warning)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func loadFrames() async {
        stopPlayback()
        isLoading = true
        loadingProgress = 0
        loadedFrameCount = 0
        sparseWarning = nil
        frames = []
        currentFrame = 0

        let urls = await helioviewerService.getAnimationFrameURLs(
            measurement: measurement,
            startDate: startDate,
            endDate: endDate,
            frameCount: frameCount,
            width: 1024,
            height: 1024
        )

        totalExpectedFrames = urls.count

        var failedCount = 0
        for (idx, frame) in urls.enumerated() {
            if Task.isCancelled { return }

            do {
                let (data, response) = try await URLSession.shared.data(from: frame.url)
                if Task.isCancelled { return }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    failedCount += 1
                    await MainActor.run {
                        loadingProgress = Double(idx + 1) / Double(urls.count)
                        loadedFrameCount = idx + 1
                    }
                    continue
                }

                if let img = UIImage(data: data) {
                    await MainActor.run {
                        let newFrame = LoadedFrame(date: frame.date, image: img)
                        frames.append(newFrame)
                        loadingProgress = Double(idx + 1) / Double(urls.count)
                        loadedFrameCount = idx + 1

                        if frames.count == 1 {
                            startPlayback()
                        }
                    }
                } else {
                    failedCount += 1
                    await MainActor.run {
                        loadingProgress = Double(idx + 1) / Double(urls.count)
                        loadedFrameCount = idx + 1
                    }
                }
            } catch {
                failedCount += 1
                await MainActor.run {
                    loadingProgress = Double(idx + 1) / Double(urls.count)
                    loadedFrameCount = idx + 1
                }
            }
        }

        if !Task.isCancelled {
            await MainActor.run {
                isLoading = false
                if frames.count < 4 && frames.count > 0 {
                    sparseWarning = "Only \(frames.count) unique frame\(frames.count == 1 ? "" : "s") found. Try a wider time range for a smoother animation."
                } else if frames.isEmpty {
                    sparseWarning = "No frames found for this time range. Try a different range or instrument."
                }
            }
        }
    }

    private func startPlayback() {
        guard !frames.isEmpty else { return }
        isPlaying = true
        playbackTask?.cancel()
        playbackTask = Task { @MainActor in
            while isPlaying && !frames.isEmpty {
                try? await Task.sleep(for: .seconds(playbackSpeed))
                guard isPlaying, !frames.isEmpty else { break }
                currentFrame = (currentFrame + 1) % frames.count
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }
}
