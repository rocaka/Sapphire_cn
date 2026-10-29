#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import SwiftUI

struct MonitoringSettingsView: View {
    @EditingSettings private var settings: SettingsEditingSession
    @ObservedObject private var stats = StatsManager.shared
    @ObservedObject private var alerts = SystemAlertsManager.shared
    @ObservedObject private var helper = HelperManager.shared
    @State private var requester = "MonitoringSettingsView." + UUID().uuidString
    @State private var pageVisible = false
    @State private var applicationActive = false
    @State private var sleeping = false
    @State private var sensorsExpanded = false
    @State private var diagnosticsExpanded = false
    @State private var sensorGroup: SensorGroup?
    @State private var sensorPage = 0
    @State private var sensorReadings: [String: Double] = [:]

    private var sampling: Bool { pageVisible && applicationActive && !sleeping }
    private var catalog: [any Sensor_p] {
        stats.allSensors.filter { sensorGroup == nil || $0.group == sensorGroup }
    }
    private var sensorBounds: Range<Int> {
        PublicMonitoringFormat.pageBounds(count: catalog.count, requestedPage: sensorPage)
    }
    private var visibleSensors: [any Sensor_p] { Array(catalog[sensorBounds]) }
    private var temperatureAvailable: Bool {
        helper.isRunning && stats.allSensors.contains { $0.group == .CPU && $0.type == .temperature }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Monitoring").font(.title2.bold())
                    Text("View local system measurements and choose menu bar readouts and alerts.")
                        .foregroundStyle(.secondary)
                    Label(L10n.string(sampling ? "Live measurements" : "Measurements paused"), systemImage: sampling ? "waveform.path.ecg" : "pause.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                measurements
                menuBarSettings
                alertSettings
                sensorSettings
                DisclosureGroup("Sapphire operation timings", isExpanded: $diagnosticsExpanded) {
                    if diagnosticsExpanded { PublicMonitoringDiagnosticsView() }
                }
                .padding(16)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                Text("This page shares the existing samplers. Its measurements pause when the page is hidden, Sapphire is inactive, or the Mac sleeps. Enabled readouts and alerts keep their own subscriptions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(25)
        }
        .onAppear {
            pageVisible = true
            applicationActive = NSApplication.shared.isActive
            sleeping = false
            reconcileSampling()
            alerts.refreshNotificationAccess()
        }
        .onDisappear { stopPage() }
        .onReceive(NotificationCenter.default.publisher(for: .sapphireSettingsWillClose)) { _ in stopPage() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            applicationActive = false
            reconcileSampling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            applicationActive = true
            reconcileSampling()
            if pageVisible { alerts.refreshNotificationAccess() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            sleeping = true
            reconcileSampling()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            sleeping = false
            applicationActive = NSApplication.shared.isActive
            reconcileSampling()
        }
        .onChange(of: stats.allSensors.map(\.key)) { _, _ in reconcileSampling() }
        .onReceive(stats.sensorSamples) { sample in
            guard sampling, sensorsExpanded, helper.isRunning else { return }
            let wanted = Set(visibleSensors.map(\.key))
            sensorReadings = Dictionary(sample.sensors.filter { wanted.contains($0.key) }.map { ($0.key, $0.value) }, uniquingKeysWith: { _, latest in latest })
        }
        .onChange(of: sensorsExpanded) { _, _ in
            sensorReadings = [:]
            reconcileSampling()
        }
        .onChange(of: sensorGroup) { _, _ in
            sensorPage = 0
            sensorReadings = [:]
            reconcileSampling()
        }
        .onChange(of: sensorPage) { _, _ in
            sensorReadings = [:]
            reconcileSampling()
        }
        .onChange(of: helper.isRunning) { _, _ in
            sensorReadings = [:]
            reconcileSampling()
        }
    }

    private var measurements: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            metricCard("CPU Usage", icon: "cpu") {
                metricValue(PublicMonitoringFormat.percent(stats.currentStats?.cpu?.totalUsage))
                if let cpu = stats.currentStats?.cpu {
                    usageBar(cpu.totalUsage)
                    valueRow("User", value: PublicMonitoringFormat.percent(cpu.userLoad))
                    valueRow("System", value: PublicMonitoringFormat.percent(cpu.systemLoad))
                }
            }
            metricCard("Memory Usage", icon: "memorychip") {
                if let ram = stats.currentStats?.ram, ram.total.isFinite, ram.total > 0,
                   ram.used.isFinite, ram.used >= 0, ram.used <= ram.total {
                    metricValue(PublicMonitoringFormat.percent(ram.usage))
                    usageBar(ram.usage)
                    valueRow("Used", value: PublicMonitoringFormat.bytes(ram.used))
                    valueRow("Total", value: PublicMonitoringFormat.bytes(ram.total))
                    valueRow("Memory Pressure", value: L10n.string(ram.pressure.value.rawValue))
                    valueRow("Swap Used", value: PublicMonitoringFormat.bytes(ram.swap.used))
                } else { metricValue(nil) }
            }
            metricCard("GPU Usage", icon: "display") {
                metricValue(PublicMonitoringFormat.percent(stats.currentStats?.gpu?.utilization))
                if let gpu = stats.currentStats?.gpu {
                    usageBar(gpu.utilization)
                    Text(gpu.model).font(.caption).foregroundStyle(.secondary)
                }
            }
            metricCard("Disk Space", icon: "internaldrive") {
                if let disk = stats.currentStats?.disk, disk.size > 0, disk.free >= 0, disk.free <= disk.size {
                    metricValue(PublicMonitoringFormat.percent(disk.percentage))
                    usageBar(disk.percentage)
                    valueRow("Available", value: PublicMonitoringFormat.bytes(Double(disk.free)))
                    valueRow("Total", value: PublicMonitoringFormat.bytes(Double(disk.size)))
                    Text(disk.mediaName.isEmpty ? disk.BSDName : disk.mediaName)
                        .font(.caption).foregroundStyle(.secondary)
                } else { metricValue(nil) }
            }
        }
    }

    private var menuBarSettings: some View {
        section("Menu Bar Readouts") {
            Toggle("Enable Menu Bar Readouts", isOn: $settings.settings.monitoringMenuBarReadoutsEnabled)
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show CPU Usage", isOn: $settings.settings.monitoringReadoutShowCPU)
                Toggle("Show Memory Usage", isOn: $settings.settings.monitoringReadoutShowMemory)
                Toggle("Show Network Rates", isOn: $settings.settings.monitoringReadoutShowNetwork)
            }
            .disabled(!settings.settings.monitoringMenuBarReadoutsEnabled)
            Text("Network rates appear in the menu bar when enabled.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var alertSettings: some View {
        section("System Alerts") {
            Toggle("Enable Alerts", isOn: $settings.settings.monitoringAlertsEnabled)
            valueRow("Notification Access", value: notificationAccessText)
            if alerts.notificationAccess == .denied {
                Text("Allow Sapphire notifications in System Settings to receive alerts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Sustained CPU Load", isOn: $settings.settings.monitoringAlertSustainedCPUEnabled)
                    Text("Notify when CPU stays above the threshold for about a minute.").font(.caption).foregroundStyle(.secondary)
                    threshold("CPU Threshold", value: $settings.settings.monitoringAlertCPUThreshold, range: 50...100, fallback: 90, unit: "%")
                        .disabled(!settings.settings.monitoringAlertSustainedCPUEnabled)
                }
                Toggle("Memory Pressure", isOn: $settings.settings.monitoringAlertMemoryPressureEnabled)
                Text("Notify when macOS reports memory pressure.").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Low Disk Space", isOn: $settings.settings.monitoringAlertLowDiskEnabled)
                    Text("Notify when the startup disk is nearly full.").font(.caption).foregroundStyle(.secondary)
                    threshold("Free Space Threshold", value: $settings.settings.monitoringAlertDiskThresholdGB, range: 2...50, fallback: 10, unit: "GB")
                        .disabled(!settings.settings.monitoringAlertLowDiskEnabled)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("High Temperature", isOn: $settings.settings.monitoringAlertTemperatureEnabled)
                        .disabled(!temperatureAvailable && !settings.settings.monitoringAlertTemperatureEnabled)
                    Text("Notify when the CPU stays above the threshold for 30 seconds. Requires the Sapphire helper.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !temperatureAvailable {
                        Text("CPU temperature is unavailable. A running, trusted helper and a supported sensor are required.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    threshold("Temperature Threshold", value: $settings.settings.monitoringAlertTemperatureThreshold, range: 70...105, fallback: 95, unit: "°C")
                        .disabled(!settings.settings.monitoringAlertTemperatureEnabled || !temperatureAvailable)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Low Battery", isOn: $settings.settings.monitoringAlertLowBatteryEnabled)
                    Text("Notify once per discharge when the battery reaches the threshold.").font(.caption).foregroundStyle(.secondary)
                    threshold("Battery Threshold", value: $settings.settings.monitoringAlertLowBatteryThreshold, range: 5...50, fallback: 15, unit: "%")
                        .disabled(!settings.settings.monitoringAlertLowBatteryEnabled)
                }
            }
            .disabled(!settings.settings.monitoringAlertsEnabled)
        }
    }

    private var sensorSettings: some View {
        section("Power and Sensors") {
            valueRow("Privileged Helper", value: L10n.string(helper.isRunning ? "Running" : "Unavailable"))
            DisclosureGroup("Latest sensor readings", isExpanded: $sensorsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if let battery = stats.currentStats?.battery {
                        valueRow("Battery Level", value: PublicMonitoringFormat.percent(battery.level))
                        // The existing battery reader uses zero when an IORegistry
                        // property is missing, so do not present that fallback as
                        // a measured zero-watt power draw.
                        valueRow("Battery Draw", value: battery.voltage > 0 && battery.amperage != 0 ? PublicMonitoringFormat.measurement(abs(battery.powerDraw), unit: "W") : nil)
                    }
                    if helper.isRunning {
                        Picker("Sensor Group", selection: $sensorGroup) {
                            Text("All Sensors").tag(Optional<SensorGroup>.none)
                            ForEach(SensorGroup.allCases, id: \.self) { group in
                                Text(L10n.string(group.rawValue)).tag(Optional(group))
                            }
                        }
                        if visibleSensors.isEmpty {
                            Text("No supported sensors are available.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(visibleSensors, id: \.key) { sensor in
                            valueRow(sensor.name, value: sensorValue(sensor))
                        }
                        if catalog.count > 12 {
                            HStack {
                                Button("Previous") { sensorPage = max(0, sensorPage - 1) }.disabled(sensorBounds.lowerBound == 0)
                                Spacer()
                                Text("\(sensorBounds.lowerBound + 1)–\(sensorBounds.upperBound) / \(catalog.count)").monospacedDigit().font(.caption)
                                Spacer()
                                Button("Next") { sensorPage += 1 }.disabled(sensorBounds.upperBound >= catalog.count)
                            }
                        }
                    } else {
                        Text("Sensor readings are unavailable without the trusted Sapphire helper. Basic CPU, memory, GPU and disk measurements remain available.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Only this page of sensors is requested. A catalog entry without a reported measurement is shown as unavailable.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
        }
    }

    private var notificationAccessText: String {
        switch alerts.notificationAccess {
        case .allowed: L10n.string("Allowed")
        case .denied: L10n.string("Denied")
        case .unknown: L10n.string("Not Requested")
        }
    }

    private func sensorValue(_ sensor: any Sensor_p) -> String? {
        guard helper.isRunning, sensor.type != .unknown else { return nil }
        return PublicMonitoringFormat.measurement(sensorReadings[sensor.key], unit: sensor.unit, minimum: sensor.type == .temperature ? 10 : 0)
    }

    private func stopPage() {
        pageVisible = false
        reconcileSampling()
    }

    private func reconcileSampling() {
        var requested: Set<StatType> = sampling ? [.cpu, .ram, .gpu, .disk] : []
        if sampling && sensorsExpanded { requested.insert(.batteryPower) }
        stats.setPolling(for: requester, requiredStats: requested, interval: .seconds(3))
        let keys = sampling && sensorsExpanded && helper.isRunning ? Set(visibleSensors.filter { $0.type != .unknown }.map(\.key)) : []
        stats.setSensorKeys(for: requester, keys: keys, interval: 3)
        if sampling && helper.isRunning { stats.requestSensorCatalog() }
        if !sampling { sensorReadings = [:] }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func metricCard<Content: View>(_ title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.headline)
            content()
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 185, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func metricValue(_ value: String?) -> some View {
        Text(value ?? L10n.string("Unavailable")).font(.title2.weight(.semibold)).monospacedDigit()
    }

    @ViewBuilder private func usageBar(_ value: Double?) -> some View {
        if let fraction = PublicMonitoringFormat.fraction(value) { ProgressView(value: fraction).tint(.accentColor) }
    }

    private func valueRow(_ title: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.string(title)).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value ?? L10n.string("Unavailable")).monospacedDigit().multilineTextAlignment(.trailing)
        }.font(.caption)
    }

    private func threshold(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, fallback: Double, unit: String) -> some View {
        let safe = Binding(get: { PublicMonitoringFormat.bounded(value.wrappedValue, in: range, fallback: fallback) }, set: { value.wrappedValue = PublicMonitoringFormat.bounded($0, in: range, fallback: fallback) })
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(PublicMonitoringFormat.measurement(safe.wrappedValue, unit: unit) ?? "").font(.caption).monospacedDigit()
            }
            Slider(value: safe, in: range, step: 1)
        }
    }
}

private struct PublicMonitoringDiagnosticsView: View {
    @ObservedObject private var monitor = ProcessCPUMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("These are elapsed times for instrumented Sapphire operations, not per-process CPU percentages.")
                .font(.caption).foregroundStyle(.secondary)
            if !monitor.isEnabled {
                Text("Performance diagnostics are disabled.").font(.caption).foregroundStyle(.secondary)
            } else if monitor.operations.isEmpty {
                Text("No operation timings have been collected.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(monitor.topConsumers(limit: 10)) { operation in
                    HStack {
                        Text(operation.name).lineLimit(1).help(operation.name)
                        Spacer()
                        Text(PublicMonitoringFormat.measurement(operation.totalTime * 1000, unit: "ms") ?? "—")
                            .monospacedDigit()
                    }.font(.caption)
                }
            }
        }.padding(.top, 10)
    }
}
#endif
