import SwiftUI
import Charts

/// X-ray flux chart - shows data for the selected time range
/// Chart range matches the filter (6h, 1d, 3d, 7d) ending at "now"
struct XRayFluxChart: View {
    @Bindable var viewModel: SpaceWeatherViewModel
    let height: CGFloat
    
    // Reference date for chart end - actual "now"
    @State private var referenceDate: Date = Date()
    
    init(viewModel: SpaceWeatherViewModel, height: CGFloat = 120) {
        self.viewModel = viewModel
        self.height = height
    }
    
    // Chart shows from (now - timeRange) to now
    private var chartStartDate: Date {
        referenceDate.addingTimeInterval(-viewModel.overlayTimeRangeHours * 3600)
    }
    
    private var chartEndDate: Date {
        referenceDate  // Actual now
    }
    
    // Get the most recent flux reading
    private var currentFlux: XRayFluxDataPoint? {
        viewModel.xrayFluxData.last
    }
    
    // Format time range for display
    private var timeRangeLabel: String {
        let hours = viewModel.overlayTimeRangeHours
        if hours < 24 { return "\(Int(hours))h" }
        else if hours == 24 { return "1d" }
        else { return "\(Int(hours / 24))d" }
    }
    
    // Flare class thresholds (log10 values)
    private let flareClasses: [(name: String, logValue: Double, color: Color)] = [
        ("X", -4, .red),
        ("M", -5, .orange),
        ("C", -6, .yellow),
        ("B", -7, .green),
        ("A", -8, .blue)
    ]
    
    // Y-axis range - fixed to show all flare classes
    private var yAxisRange: ClosedRange<Double> {
        return -8.5 ... -3.5  // A to X+ range
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with current value
            HStack {
                HStack(spacing: 4) {
                    Text("X-Ray Flux")
                        .font(Theme.mono(12))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(timeRangeLabel)
                        .font(Theme.mono(10))
                        .foregroundStyle(.white.opacity(0.4))
                }
                
                Spacer()
                
                if let flux = currentFlux {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForClass(flux.estimatedClass))
                            .frame(width: 8, height: 8)
                        Text(flux.estimatedClass)
                            .font(Theme.mono(15, weight: .bold))
                            .foregroundStyle(colorForClass(flux.estimatedClass))
                        
                        if let fluxValue = flux.flux {
                            Text("(\(formatFlux(fluxValue)))")
                                .font(Theme.mono(11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }
            
            // Chart - shows full time range
            if viewModel.isLoadingFlux {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.orange)
                        Text("Loading \(timeRangeLabel) data...")
                            .font(Theme.mono(12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .frame(height: height)
            } else if viewModel.xrayFluxData.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.orange)
                        Text("Loading flux data...")
                            .font(Theme.mono(12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .frame(height: height)
            } else {
                Chart {
                    // Flare class threshold lines with labels
                    ForEach(flareClasses, id: \.name) { flareClass in
                        RuleMark(y: .value("Class", flareClass.logValue))
                            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(flareClass.color.opacity(0.4))
                    }
                    
                    // SXR-A flux line (shorter wavelength, more energetic) - lighter
                    ForEach(viewModel.chartFluxDataA) { point in
                        if let date = point.date, let flux = point.flux, flux > 0 {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Flux", log10(flux)),
                                series: .value("Channel", "SXR-A")
                            )
                            .foregroundStyle(.cyan)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        }
                    }
                    
                    // SXR-B flux line (primary for classification) - prominent
                    ForEach(viewModel.chartFluxData) { point in
                        if let date = point.date, let flux = point.flux, flux > 0 {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Flux", log10(flux)),
                                series: .value("Channel", "SXR-B")
                            )
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                    }
                    
                    // Current time indicator
                    RuleMark(x: .value("Now", referenceDate))
                        .foregroundStyle(Theme.accentColor.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartForegroundStyleScale([
                    "SXR-A": Color.cyan,
                    "SXR-B": Color.orange
                ])
                .chartYScale(domain: yAxisRange)
                .chartXScale(domain: chartStartDate...chartEndDate)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: flareClasses.map { $0.logValue }) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel {
                            if let v = value.as(Double.self),
                               let flareClass = flareClasses.first(where: { $0.logValue == v }) {
                                Text(flareClass.name)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(flareClass.color)
                            }
                        }
                    }
                }
                .chartXAxis {
                    // Adjust axis marks based on window size
                    let hours = viewModel.overlayTimeRangeHours
                    AxisMarks(values: .stride(by: hours <= 24 ? .hour : .day, count: hours <= 24 ? 6 : 1)) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                    }
                }
                .frame(height: height)
                .drawingGroup()
            }
            
            // Legend and time labels
            HStack {
                Text(formatTimeLabel(chartStartDate))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                
                Spacer()
                
                // Legend
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.cyan)
                            .frame(width: 12, height: 2)
                        Text("0.5-4Å")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.orange)
                            .frame(width: 12, height: 2)
                        Text("1-8Å")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                
                Spacer()
                
                Text(formatTimeLabel(chartEndDate))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: viewModel.xrayFluxData.count) { _, _ in
            // Update reference date when new data loads
            referenceDate = Date()
        }
        .onChange(of: viewModel.overlayTimeRangeHours) { _, _ in
            // Update reference date when time range changes
            referenceDate = Date()
        }
    }
    
    private func colorForClass(_ flareClass: String) -> Color {
        if flareClass.hasPrefix("X") { return .red }
        if flareClass.hasPrefix("M") { return .orange }
        if flareClass.hasPrefix("C") { return .yellow }
        if flareClass.hasPrefix("B") { return .green }
        return .blue
    }
    
    private func formatFlux(_ value: Double) -> String {
        String(format: "%.1e", value)
    }
    
    private func formatTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")  // All SWPC data is in UTC
        let hours = viewModel.overlayTimeRangeHours
        
        // For smaller windows, show time; for larger windows, show date
        if hours <= 6 {
            formatter.dateFormat = "HH:mm"
        } else if hours <= 24 {
            formatter.dateFormat = "MMM d HH:mm"
        } else {
            formatter.dateFormat = "MMM d"
        }
        
        return formatter.string(from: date) + " UTC"
    }
}
