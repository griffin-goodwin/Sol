import SwiftUI

/// Solar view with multiple instruments and animation capability
struct SDOImageView: View {
    @Bindable var viewModel: SpaceWeatherViewModel
    @State private var isFullScreen = false
    @State private var selectedInstrument: SolarInstrument = .sdoAIA
    
    // Time selection
    @State private var selectedDate: Date = Date()
    @State private var isLoadingImage = false
    @State private var instrumentImageURL: URL?
    @State private var dateDebounceTask: Task<Void, Never>?
    
    // Animation (custom bottom drawer overlay to avoid iOS sheet background scaling/"zoom")
    @State private var showAnimationDrawer = false
    
    private let helioviewerService = HelioviewerService()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient that changes with wavelength/instrument
                DynamicColorBackground(accentColor: instrumentColor)
                    .animation(.easeInOut(duration: 0.5), value: instrumentColor.description)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Instrument selector
                        instrumentSelector
                        
                        // Main image section
                        imageSection
                        .onTapGesture {
                            isFullScreen = true
                        }
                    
                        // Wavelength bar (only for AIA)
                        if selectedInstrument == .sdoAIA {
                            wavelengthBar
                        }
                        
                        // Time controls (available for all instruments)
                        timeControlsSection
                        
                        // Animation (dropdown drawer)
                        animationButton
                        
                        // Instrument info
                        instrumentInfoSection
                    }
                    .padding(.vertical)
                }
                .scrollContentBackground(.hidden)
                // When the animation drawer is open, visually separate foreground/background
                .blur(radius: showAnimationDrawer ? 8 : 0)
                .overlay {
                    if showAnimationDrawer {
                        // Extra dim layer
                        Color.black.opacity(0.3).ignoresSafeArea()
                    }
                }
                .allowsHitTesting(!showAnimationDrawer)
                
                if showAnimationDrawer {
                    // Dimmed backdrop
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
                            instrument: selectedInstrument,
                            wavelength: viewModel.selectedWavelength,
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
                    Text("SOL.SWx")
                        .font(Theme.mono(42, weight: .black))
                        .tracking(3)
                        .foregroundStyle(Theme.solarTitleGradient)
                        .shadow(color: Theme.accentColor.opacity(0.5), radius: 8, x: 0, y: 0)
                        .offset(x: 10) // Offset to compensate for trailing button
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
                    imageURL: currentImageURL,
                    instrument: selectedInstrument,
                    isPresented: $isFullScreen
                )
            }
        }
        .task {
            await loadInstrumentImage()
        }
        .onChange(of: selectedInstrument) { _, _ in
            Task { await loadInstrumentImage() }
        }
        .onChange(of: viewModel.selectedWavelength) { _, _ in
            if selectedInstrument == .sdoAIA {
                Task { await loadInstrumentImage() }
            }
        }
    }
    
    // MARK: - Current Image URL
    
    private var currentImageURL: URL? {
        return instrumentImageURL
    }
    
    // MARK: - Instrument Selector
    
    private var instrumentSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(SolarInstrument.allCases) { instrument in
                    InstrumentChip(
                        instrument: instrument,
                        isSelected: selectedInstrument == instrument,
                        wavelength: instrument == .sdoAIA ? viewModel.selectedWavelength : nil
                    ) {
                        withAnimation(Theme.Animation.spring) {
                            selectedInstrument = instrument
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
                                .tint(instrumentColor)
                            Text("Loading \(selectedInstrument.displayName)...")
                                .font(Theme.mono(12, weight: .medium))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                    .shimmer()
            } else if let url = currentImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                ProgressView()
                                    .scaleEffect(1.4)
                                    .tint(instrumentColor)
                            }
                            .shimmer()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
                            .shadow(color: instrumentColor.opacity(0.5), radius: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [instrumentColor.opacity(0.3), instrumentColor.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    case .failure:
                        RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                VStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 32))
                                        .foregroundStyle(instrumentColor.opacity(0.6))
                                    Text("Unable to load image")
                                        .font(Theme.mono(12, weight: .medium))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
                .id(url)  // Force view recreation with animation when URL changes
                .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: selectedInstrument.icon)
                                .font(.system(size: 36))
                                .foregroundStyle(instrumentColor.opacity(0.6))
                            Text("Tap refresh to load")
                                .font(Theme.mono(12, weight: .medium))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: currentImageURL)
        .animation(.easeInOut(duration: 0.3), value: isLoadingImage)
        .padding(.horizontal)
    }
    
    // MARK: - Wavelength Bar
    
    private var wavelengthBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SDOWavelength.allCases) { wavelength in
                    WavelengthChip(
                        wavelength: wavelength,
                        isSelected: viewModel.selectedWavelength == wavelength
                    ) {
                        Task {
                            await viewModel.selectWavelength(wavelength)
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
                
                HStack(spacing: 8) {
                    QuickTimeButton(title: "Now") {
                        selectedDate = Date()
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
                }
            }
            
            // --- CUSTOM DATEPICKER UI ---
            HStack {
                // Date Part
                Text(selectedDate.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(Theme.mono(14))
                    .foregroundStyle(.white)
                    .overlay {
                        DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .colorMultiply(.clear)
                    }
                
                Spacer()
                
                // Time Part
                Text(selectedDate.formatted(.dateTime.hour().minute()))
                    .font(Theme.mono(14))
                    .foregroundStyle(.white)
                    .overlay {
                        DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .colorMultiply(.clear)
                    }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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

    
    // MARK: - Animation Button (opens a dropdown sheet)
    
    private var animationButton: some View {
        Button {
            withAnimation(Theme.Animation.spring) {
                showAnimationDrawer = true
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(instrumentColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(instrumentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Animation")
                        .font(Theme.mono(14, weight: .semibold))
                    Text("Generate a timelapse for \(selectedInstrument.displayName)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.tertiaryText)
                }
                
                Spacer()
                
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.quaternaryText)
            }
            .foregroundStyle(.white)
            .padding(Theme.Spacing.md)
            .background(instrumentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(instrumentColor.opacity(0.2), lineWidth: 1)
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
                        .fill(instrumentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: selectedInstrument.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(instrumentColor)
                }
                Text(selectedInstrument.displayName)
                    .font(Theme.mono(15, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            Text(selectedInstrument.description)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.secondaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            
            if selectedInstrument == .sdoAIA {
                Text(viewModel.selectedWavelength.description)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.top, Theme.Spacing.xs)
            }
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
        
        instrumentImageURL = await helioviewerService.getInstrumentImageURL(
            date: selectedDate,
            instrument: selectedInstrument,
            wavelength: selectedInstrument == .sdoAIA ? viewModel.selectedWavelength : nil,
            width: 1024,
            height: 1024
        )
        
        isLoadingImage = false
    }
    
    private var instrumentColor: Color {
        // Use wavelength-specific color for AIA, instrument-specific for others
        if selectedInstrument == .sdoAIA {
            return wavelengthColor(viewModel.selectedWavelength)
        }
        // LASCO C2 is orange/red, C3 is blue (matches actual image colors)
        switch selectedInstrument {
        case .sohoLASCO_C2: return .orange
        case .sohoLASCO_C3: return .blue
        default: return .orange
        }
    }
    
    private func wavelengthColor(_ wavelength: SDOWavelength) -> Color {
        switch wavelength.color {
        case "green": return .green
        case "teal": return .teal
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "blue": return .blue
        case "pink": return .pink
        case "gray": return .gray
        default: return .orange
        }
    }
}

// MARK: - Supporting Views

struct InstrumentChip: View {
    let instrument: SolarInstrument
    let isSelected: Bool
    var wavelength: SDOWavelength? = nil  // For AIA to show wavelength color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(chipColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: isSelected ? chipColor.opacity(0.5) : .clear, radius: 4)
                Text(instrument.rawValue)
                    .font(Theme.mono(13, weight: isSelected ? .bold : .medium))
            }
            .foregroundStyle(isSelected ? .white : Theme.secondaryText)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? chipColor.opacity(0.2) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? chipColor.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(Theme.Animation.spring, value: isSelected)
    }
    
    private var chipColor: Color {
        // For AIA, use wavelength color if available
        if instrument == .sdoAIA, let wl = wavelength {
            return wavelengthColor(wl)
        }
        // LASCO C2 is orange/red, C3 is blue (matches actual image colors)
        switch instrument {
        case .sdoAIA: return .orange
        case .sohoLASCO_C2: return .orange
        case .sohoLASCO_C3: return .blue
        }
    }
    
    private func wavelengthColor(_ wavelength: SDOWavelength) -> Color {
        switch wavelength.color {
        case "green": return .green
        case "teal": return .teal
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "blue": return .blue
        case "pink": return .pink
        case "gray": return .gray
        default: return .orange
        }
    }
}

struct QuickTimeButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
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

struct WavelengthChip: View {
    let wavelength: SDOWavelength
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(wavelengthColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: isSelected ? wavelengthColor.opacity(0.5) : .clear, radius: 4)
                Text(wavelength.rawValue)
                    .font(Theme.mono(13, weight: isSelected ? .bold : .medium))
            }
            .foregroundStyle(isSelected ? .white : Theme.secondaryText)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? wavelengthColor.opacity(0.2) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? wavelengthColor.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(Theme.Animation.spring, value: isSelected)
    }
    
    private var wavelengthColor: Color {
        switch wavelength.color {
        case "green": return .green
        case "teal": return .teal
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "blue": return .blue
        case "pink": return .pink
        case "gray": return .gray
        default: return .white
        }
    }
}

// MARK: - Full Screen View

struct FullScreenInstrumentView: View {
    let imageURL: URL?
    let instrument: SolarInstrument
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
                    Text(instrument.displayName)
                        .font(Theme.mono(16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    
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


// MARK: - Animation Drawer (custom bottom panel)

private struct AnimationDrawer: View {
    let instrument: SolarInstrument
    let wavelength: SDOWavelength
    let helioviewerService: HelioviewerService
    @Binding var isPresented: Bool
    
    @State private var startDate: Date = Date().addingTimeInterval(-24 * 3600)
    @State private var endDate: Date = Date()
    @State private var frameCount: Int = 24
    
    @State private var isLoading = false
    @State private var loadingProgress: Double = 0
    
    @State private var frames: [LoadedFrame] = []
    @State private var currentFrame: Int = 0
    @State private var isPlaying = false
    @State private var playbackSpeed: Double = 0.15
    @State private var playbackTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?
    
    private let frameCounts = [12, 24, 48, 72]
    
    var body: some View {
        VStack(spacing: 12) {
            // Grabber + header
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
                        Text(instrument.displayName)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.accentColor)
                    }
                    
                    Spacer()
                    
                    Button {
                        stopPlayback()
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
            
            if frames.isEmpty {
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
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .onDisappear { stopPlayback() }
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
                    HStack(spacing: 12) {
                        ProgressView(value: loadingProgress)
                            .frame(width: 120)
                            .tint(Theme.accentColor)
                        Text("\(Int(loadingProgress * 100))%")
                            .font(Theme.mono(12, weight: .bold))
                            .foregroundStyle(Theme.accentColor)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 20)
                    
                    Spacer()
                }
            }
        }
        .frame(height: UIScreen.main.bounds.height * 0.35)
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
    }
    
    private var config: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                // Start Date
                datePickerRow(label: "Start", selection: $startDate, range: ...endDate)
                
                // End Date
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
                    UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Theme.accentColor)
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
                .background(Theme.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Theme.accentColor.opacity(0.3), radius: 10, y: 0)
            }
            .disabled(isLoading)
        }
    }

    // Helper function to keep the code clean and ensure consistent formatting
    @ViewBuilder
    private func datePickerRow(label: String, selection: Binding<Date>, range: ClosedRange<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: "calendar")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondaryText)
            
            HStack {
                // Date Part
                Text(selection.wrappedValue.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(Theme.mono(14))
                    .foregroundStyle(.white)
                    .overlay {
                        DatePicker("", selection: selection, in: range, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Theme.accentColor)
                            .colorMultiply(.clear)
                    }
                
                Spacer()
                
                // Time Part
                Text(selection.wrappedValue.formatted(.dateTime.hour().minute()))
                    .font(Theme.mono(14))
                    .foregroundStyle(.white)
                    .overlay {
                        DatePicker("", selection: selection, in: range, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(Theme.accentColor)
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

    // Overload for the partial range (Start Date uses ...endDate)
    @ViewBuilder
    private func datePickerRow(label: String, selection: Binding<Date>, range: PartialRangeThrough<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: "calendar")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondaryText)
            
            HStack {
                // Date Part
                Text(selection.wrappedValue.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(Theme.mono(14))
                    .foregroundStyle(.white)
                    .overlay {
                        DatePicker("", selection: selection, in: range, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Theme.accentColor)
                            .colorMultiply(.clear)
                    }
                
                Spacer()
                
                // Time Part
                Text(selection.wrappedValue.formatted(.dateTime.hour().minute()))
                    .font(Theme.mono(14))
                    .foregroundStyle(.white)
                    .overlay {
                        DatePicker("", selection: selection, in: range, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(Theme.accentColor)
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
                        .foregroundStyle(Theme.accentColor)
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
                        .tint(Theme.accentColor)
                    }
                    
                    HStack {
                        Text("\(currentFrame + 1)/\(frames.count)")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Text("\(Int(1/playbackSpeed)) FPS")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.accentColor)
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
        }
    }
    
    private func loadFrames() async {
        stopPlayback()
        isLoading = true
        loadingProgress = 0
        frames = []
        currentFrame = 0
        
        let urls = await helioviewerService.getAnimationFrameURLs(
            instrument: instrument,
            wavelength: instrument == .sdoAIA ? wavelength : nil,
            startDate: startDate,
            endDate: endDate,
            frameCount: frameCount,
            width: 1024,
            height: 1024
        )
        
        for (idx, frame) in urls.enumerated() {
            if Task.isCancelled { return }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: frame.url)
                if Task.isCancelled { return }
                
                if let img = UIImage(data: data) {
                    await MainActor.run {
                        frames.append(LoadedFrame(date: frame.date, image: img))
                        loadingProgress = Double(idx + 1) / Double(urls.count)
                        
                        // Start playing as soon as the first frame arrives
                        if frames.count == 1 {
                            startPlayback()
                        }
                    }
                }
            } catch {
                print("Failed to load frame \(idx): \(error)")
            }
        }
        
        if !Task.isCancelled {
            await MainActor.run { isLoading = false }
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
