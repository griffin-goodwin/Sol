import SwiftUI

/// Detailed view for a single space weather event
struct EventDetailView: View {
    let event: SpaceWeatherEvent
    var viewModel: SpaceWeatherViewModel?
    @Environment(\.openURL) private var openURL
    @State private var eventImageURL: URL?
    @State private var eventWCS: SolarWCS?
    @State private var isLoadingImage = true
    @State private var selectedWavelength: SDOWavelength = .aia171
    @State private var selectedInstrument: SolarInstrument = .sdoAIA
    @State private var showWavelengthSheet = false
    
    /// Whether this event should show LASCO instead of AIA
    private var isCMEEvent: Bool {
        event.type == .cme
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header card
                headerCard
                
                // Details section
                detailsSection
                
                // Information section
                infoSection
                
                // Link to NASA
                if let link = event.link, let url = URL(string: link) {
                    linkSection(url: url)
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundGradient)
        .navigationTitle(event.type.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            // Use LASCO for CME events, SDO AIA for others
            if isCMEEvent {
                selectedInstrument = .sohoLASCO_C2
            } else if let viewModel = viewModel {
                selectedWavelength = viewModel.selectedWavelength
            }
            await loadEventImage()
        }
    }
    
    private var headerCard: some View {
        VStack(spacing: 16) {
            // CME events show full LASCO coronagraph image
            if isCMEEvent {
                cmeImageView
                
                // Instrument picker for LASCO
                wavelengthPicker
                
            } else if let x = event.hpcX, let y = event.hpcY {
                // Event image cutout - larger and using event-specific wavelength
                Group {
                    if isLoadingImage {
                        Circle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 280, height: 280)
                            .overlay {
                                ProgressView()
                                    .scaleEffect(1.2)
                            }
                    } else if let url = eventImageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                GeometryReader { geometry in
                                    // Use WCS for proper coordinate transform
                                    let coords = eventWCS?.hpcToNormalized(hpcX: x, hpcY: y) ?? 
                                        fallbackCoords(x: x, y: y)
                                    let normalizedX = coords.x
                                    let normalizedY = coords.y
                                    
                                    // Zoom level - larger cutout
                                    let zoom: CGFloat = 3.0
                                    
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: geometry.size.width * zoom, height: geometry.size.height * zoom)
                                        .position(
                                            x: geometry.size.width / 2 - (normalizedX - 0.5) * geometry.size.width * zoom,
                                            y: geometry.size.height / 2 - (normalizedY - 0.5) * geometry.size.height * zoom
                                        )
                                }
                                .frame(width: 280, height: 280)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(colorForType(event.type), lineWidth: 4)
                                )
                                .shadow(color: colorForType(event.type).opacity(0.5), radius: 15)
                                
                            case .empty:
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                                    .frame(width: 280, height: 280)
                                    .overlay { ProgressView() }
                            default:
                                fallbackIcon
                            }
                        }
                        .frame(width: 280, height: 280)
                    } else {
                        fallbackIcon
                    }
                }
                
                // Wavelength picker
                wavelengthPicker
                
            } else {
                // No coordinates - show fallback with explanation
                noLocationDataView
            }
            
            // Title
            Text(event.title)
                .font(Theme.mono(20, weight: .bold))
                .multilineTextAlignment(.center)
            
            // Severity badge
            SeverityBadge(severity: event.severity)
            
            // Date and time
            HStack {
                Image(systemName: "calendar")
                Text(event.date.formattedDateTime)
            }
            .font(Theme.mono(14))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var wavelengthLabel: String {
        selectedWavelength.rawValue
    }
    
    private var wavelengthPicker: some View {
        Button {
            showWavelengthSheet = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isCMEEvent ? colorForInstrument(selectedInstrument) : colorForWavelength(selectedWavelength))
                    .frame(width: 12, height: 12)
                Text(isCMEEvent ? selectedInstrument.displayName : selectedWavelength.rawValue)
                    .font(Theme.mono(13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(Theme.mono(10))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.cardBackground)
            .clipShape(Capsule())
        }
        .sheet(isPresented: $showWavelengthSheet) {
            if isCMEEvent {
                CMEInstrumentPickerSheet(
                    selectedInstrument: $selectedInstrument,
                    onSelect: {
                        Task { await loadEventImage() }
                    }
                )
            } else {
                EventWavelengthPickerSheet(
                    selectedWavelength: $selectedWavelength,
                    onSelect: {
                        Task { await loadEventImage() }
                    }
                )
            }
        }
    }
    
    private func colorForInstrument(_ instrument: SolarInstrument) -> Color {
        switch instrument {
        case .sohoLASCO_C2: return .orange
        case .sohoLASCO_C3: return .blue
        default: return .white
        }
    }
    
    /// Full LASCO coronagraph image view for CME events
    private var cmeImageView: some View {
        Group {
            if isLoadingImage {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 300, height: 300)
                    .overlay {
                        ProgressView()
                            .scaleEffect(1.2)
                    }
            } else if let url = eventImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 300, height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(colorForType(event.type), lineWidth: 3)
                            )
                            .shadow(color: colorForType(event.type).opacity(0.4), radius: 12)
                    case .empty:
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 300, height: 300)
                            .overlay { ProgressView() }
                    default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
    }
    
    private func loadEventImage() async {
        isLoadingImage = true
        if let viewModel = viewModel {
            if isCMEEvent {
                // Use LASCO for CME events
                eventImageURL = await viewModel.getLASCOImageURL(for: event, instrument: selectedInstrument)
                eventWCS = nil  // LASCO doesn't use HPC coordinates
            } else {
                eventImageURL = await viewModel.getEventImageURL(for: event, wavelength: selectedWavelength)
                eventWCS = await viewModel.getEventWCS(for: event, wavelength: selectedWavelength)
            }
        }
        isLoadingImage = false
    }
    
    private func colorForWavelength(_ wavelength: SDOWavelength) -> Color {
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
    
    private func fallbackCoords(x: Double, y: Double) -> (x: Double, y: Double) {
        // Fallback: Image is 1024x1024 at 2.4204409 arcsec/pixel
        let imageHalfWidth: Double = 1239.25
        let normalizedX = (x / imageHalfWidth) * 0.5 + 0.5
        let normalizedY = 0.5 - (y / imageHalfWidth) * 0.5
        return (normalizedX, normalizedY)
    }
    
    private var fallbackIcon: some View {
        Image(systemName: event.type.icon)
            .font(.system(size: 60))
            .foregroundStyle(colorForType(event.type))
            .padding(30)
            .background(colorForType(event.type).opacity(0.15))
            .clipShape(Circle())
    }
    
    private var noLocationDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: event.type.icon)
                .font(.system(size: 50))
                .foregroundStyle(colorForType(event.type))
                .padding(25)
                .background(colorForType(event.type).opacity(0.15))
                .clipShape(Circle())
            
            Text("No Location Data")
                .font(Theme.mono(14))
                .foregroundStyle(.secondary)
            
            Text(noLocationReason)
                .font(Theme.mono(12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var noLocationReason: String {
        switch event.type {
        case .cme:
            return "CME events are detected in coronagraph images and don't have precise solar surface coordinates."
        case .geomagneticStorm:
            return "Geomagnetic storms occur in Earth's magnetosphere, not on the Sun's surface."
        case .solarEnergeticParticle, .radiationBeltEnhancement:
            return "Particle events are detected by spacecraft instruments in space."
        case .interplanetaryShock:
            return "Interplanetary shocks are detected by spacecraft between the Sun and Earth."
        case .highSpeedStream:
            return "High speed streams originate from coronal holes which may span large areas."
        default:
            return "Location data not available for this event."
        }
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Event Details")
                    .font(Theme.mono(16, weight: .bold))
                Spacer()
                // Source badge
                SourceBadgeLarge(source: event.source)
            }
            
            Text(event.details)
                .font(Theme.mono(14))
                .foregroundStyle(.secondary)
            
            // Show strength if available for flares
            if event.type == .solarFlare, let strength = event.strengthDisplay {
                HStack {
                    Text("Intensity:")
                        .font(Theme.mono(14))
                        .foregroundStyle(.secondary)
                    Text(strength)
                        .font(Theme.mono(15, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About \(event.type.displayName)")
                .font(Theme.mono(16, weight: .bold))
            
            Text(descriptionForEventType(event.type))
                .font(Theme.mono(14))
                .foregroundStyle(.secondary)
            
            // Potential impacts
            VStack(alignment: .leading, spacing: 8) {
                Text("Potential Impacts")
                    .font(Theme.mono(14, weight: .semibold))
                
                ForEach(impactsForEventType(event.type), id: \.self) { impact in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(Theme.mono(12))
                        Text(impact)
                            .font(Theme.mono(14))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func linkSection(url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack {
                Image(systemName: "link")
                Text("View on NASA DONKI")
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .font(Theme.mono(16, weight: .bold))
            .foregroundStyle(.white)
            .padding()
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func colorForType(_ type: SpaceWeatherEventType) -> Color {
        switch type.color {
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "yellow": return .yellow
        case "blue": return .blue
        case "green": return .green
        case "cyan": return .cyan
        default: return .gray
        }
    }
    
    private func descriptionForEventType(_ type: SpaceWeatherEventType) -> String {
        switch type {
        case .cme:
            return "A Coronal Mass Ejection (CME) is a massive burst of solar wind and magnetic fields released from the Sun's corona. CMEs can contain billions of tons of matter and travel at speeds up to several million miles per hour."
        case .geomagneticStorm:
            return "A geomagnetic storm is a temporary disturbance of Earth's magnetosphere caused by a solar wind shock wave. These storms can disrupt navigation systems, create power grid fluctuations, and produce beautiful auroras."
        case .solarFlare:
            return "A solar flare is a sudden flash of increased brightness on the Sun. Flares are classified by their X-ray brightness, with X-class being the most powerful, followed by M-class and C-class."
        case .solarEnergeticParticle:
            return "Solar Energetic Particles (SEPs) are high-energy particles emitted by the Sun during solar flares and CMEs. These particles can pose radiation hazards to astronauts and damage satellites."
        case .interplanetaryShock:
            return "An interplanetary shock is a disturbance in the solar wind that travels through the solar system. These shocks can compress Earth's magnetic field and trigger geomagnetic storms."
        case .radiationBeltEnhancement:
            return "Radiation Belt Enhancement occurs when Earth's Van Allen radiation belts receive an influx of energetic particles. This can pose risks to satellites and spacecraft operating in these regions."
        case .highSpeedStream:
            return "High Speed Streams are fast-moving streams of solar wind that originate from coronal holes on the Sun. When these streams interact with Earth's magnetosphere, they can cause minor to moderate geomagnetic disturbances."
        case .activeRegion:
            return "An Active Region is an area on the Sun with a strong magnetic field. These regions are often the source of solar flares and coronal mass ejections."
        case .sunspot:
            return "Sunspots are temporary phenomena on the Sun's photosphere that appear as spots darker than the surrounding areas. They are regions of reduced surface temperature caused by concentrations of magnetic flux."
        }
    }
    
    private func impactsForEventType(_ type: SpaceWeatherEventType) -> [String] {
        switch type {
        case .cme:
            return [
                "Satellite damage and orbital changes",
                "Radio communication disruptions",
                "GPS accuracy degradation",
                "Power grid fluctuations",
                "Enhanced aurora visibility"
            ]
        case .geomagneticStorm:
            return [
                "Power grid instabilities",
                "Pipeline corrosion acceleration",
                "GPS and navigation errors",
                "HF radio blackouts",
                "Aurora visible at lower latitudes"
            ]
        case .solarFlare:
            return [
                "Radio communication blackouts",
                "Navigation system errors",
                "Increased radiation exposure for aviation",
                "Satellite electronics damage"
            ]
        case .solarEnergeticParticle:
            return [
                "Radiation hazards for astronauts",
                "Satellite system anomalies",
                "High-latitude radio absorption"
            ]
        case .interplanetaryShock:
            return [
                "Sudden magnetic field changes",
                "Triggered geomagnetic storms",
                "Satellite operational impacts"
            ]
        case .radiationBeltEnhancement:
            return [
                "Increased satellite radiation exposure",
                "Potential spacecraft charging issues",
                "Enhanced deep-space radiation"
            ]
        case .highSpeedStream:
            return [
                "Minor geomagnetic activity",
                "Possible aurora enhancement",
                "Minor satellite drag increases"
            ]
        case .activeRegion:
            return [
                "Source of solar flares",
                "Source of CMEs",
                "Increased solar activity"
            ]
        case .sunspot:
            return [
                "Indicator of solar activity",
                "Potential for flare generation",
                "Magnetic field disturbances"
            ]
        }
    }
}
// MARK: - Event Wavelength Picker Sheet

struct EventWavelengthPickerSheet: View {
    @Binding var selectedWavelength: SDOWavelength
    var onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SDOWavelength.allCases) { wavelength in
                        Button {
                            selectedWavelength = wavelength
                            onSelect()
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Circle()
                                    .fill(colorForWavelength(wavelength))
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        Circle()
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(wavelength.rawValue)
                                        .font(Theme.mono(16, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(wavelength.description)
                                        .font(Theme.mono(12))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedWavelength == wavelength {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accentColor)
                                        .font(Theme.mono(18))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("AIA/HMI Wavelengths")
                } footer: {
                    Text("Select a wavelength to view this event.")
                }
            }
            .navigationTitle("Wavelength")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func colorForWavelength(_ wavelength: SDOWavelength) -> Color {
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

// MARK: - CME Instrument Picker Sheet (LASCO)

struct CMEInstrumentPickerSheet: View {
    @Binding var selectedInstrument: SolarInstrument
    var onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    private let lascoInstruments: [SolarInstrument] = [.sohoLASCO_C2, .sohoLASCO_C3]
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(lascoInstruments) { instrument in
                        Button {
                            selectedInstrument = instrument
                            onSelect()
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: instrument.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(colorForInstrument(instrument))
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(instrument.displayName)
                                        .font(Theme.mono(16, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(instrument.description)
                                        .font(Theme.mono(12))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedInstrument == instrument {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accentColor)
                                        .font(Theme.mono(18))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("SOHO Coronagraphs")
                } footer: {
                    Text("LASCO coronagraphs block the Sun's disk to reveal the faint corona and CMEs.")
                }
            }
            .navigationTitle("Coronagraph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func colorForInstrument(_ instrument: SolarInstrument) -> Color {
        switch instrument {
        case .sohoLASCO_C2: return .orange
        case .sohoLASCO_C3: return .blue
        default: return .white
        }
    }
}