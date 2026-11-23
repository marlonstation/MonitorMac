import AppKit
import ServiceManagement
import SwiftUI

private let interfaceLocale = Locale(identifier: "en_US")

struct Theme: Identifiable {
    let id: String
    let title: String
    let accent: NSColor
    let background: NSColor
    let text: NSColor
    static let all: [Theme] = [
        Theme(id:"cyan",title:"Cyan",accent:.systemCyan,background:NSColor(white:0.08,alpha:1),text:.white),
        Theme(id:"blue",title:"Ocean",accent:.systemBlue,background:NSColor(red:0.025,green:0.06,blue:0.13,alpha:1),text:.white),
        Theme(id:"purple",title:"Violet",accent:.systemPurple,background:NSColor(red:0.09,green:0.04,blue:0.14,alpha:1),text:.white),
        Theme(id:"green",title:"Mint",accent:.systemMint,background:NSColor(red:0.025,green:0.1,blue:0.08,alpha:1),text:.white),
        Theme(id:"orange",title:"Amber",accent:.systemOrange,background:NSColor(red:0.12,green:0.065,blue:0.02,alpha:1),text:.white),
        Theme(id:"pink",title:"Rose",accent:.systemPink,background:NSColor(red:0.13,green:0.04,blue:0.07,alpha:1),text:.white),
        Theme(id:"mono",title:"Graphite",accent:.white,background:NSColor(white:0.08,alpha:1),text:.white),
        Theme(id:"light",title:"Light",accent:.systemBlue,background:NSColor(white:0.96,alpha:1),text:NSColor(white:0.08,alpha:1))
    ]
    static func find(_ id: String) -> Theme { all.first{$0.id==id} ?? all[0] }
}
final class Model: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var readings = ReadingState()
    @Published var locked = UserDefaults.standard.bool(forKey:"locked")
    @Published var cpuKey = UserDefaults.standard.string(forKey:"cpuKey") ?? "auto"
    @Published var gpuKey = UserDefaults.standard.string(forKey:"gpuKey") ?? "auto"
    @Published var opacity = UserDefaults.standard.object(forKey:"opacity") as? Double ?? 0.9
    @Published var themeID = UserDefaults.standard.string(forKey:"theme") ?? "cyan"
    @Published var stale = true
    var theme: Theme { Theme.find(themeID) }
    func reading(_ cpu: Bool) -> TemperatureReading? { cpu ? readings.cpu : readings.gpu }
    func temperature(_ cpu: Bool) -> Double? { reading(cpu)?.sensor.celsius }
    func sourceText(_ cpu: Bool) -> String { reading(cpu)?.sensor.name ?? "Waiting for a sensor" }
    func tempText(_ cpu: Bool) -> String { temperature(cpu).map{String(format:"%.0f °C",$0)} ?? "—" }
    var memoryText: String { snapshot.used.map{String(format:"%.1f / %.0f GiB",$0/1073741824,snapshot.total/1073741824)} ?? "Reading…" }
    var age: Int { [readings.cpu,readings.gpu].compactMap{$0}.map{max(0,Int(Date().timeIntervalSince($0.date)))}.max() ?? 0 }
    var footer: String {
        guard MetricsReader.hasExperimentalSensors else { return "Thermal: " + snapshot.thermal }
        return !readings.ready ? "Connecting to temperature sensors…" : stale ? "Last reading · \(age)s ago · retrying" : "Thermal: \(snapshot.thermal)" }
    var compactFooter: String {
        guard MetricsReader.hasExperimentalSensors else { return snapshot.thermal }
        return !readings.ready ? "Sensors unavailable" : stale ? "Updated \(age)s ago" : snapshot.thermal }
}
struct WindowGrip: NSViewRepresentable {
    let locked:Bool
    let moving:Bool
    var moveEnded: (() -> Void)? = nil
    let resize:(CGSize,Bool)->Void
    func makeNSView(context:Context)->GripButton { GripButton() }
    func updateNSView(_ view:GripButton,context:Context) {
        view.moving=moving;view.moveEnded=moveEnded;view.resize=resize;view.isEnabled = !locked
        view.image=NSImage(systemSymbolName:moving ? "arrow.up.and.down.and.arrow.left.and.right" : "arrow.up.left.and.arrow.down.right",accessibilityDescription:moving ? "Move window" : "Resize overlay")
        view.setAccessibilityLabel(moving ? "Move window" : "Resize overlay")
        view.toolTip=locked ? "Unlock position first" : moving ? "Hold and drag to move" : "Drag to resize (144–200 pt, square)"
    }
}
final class GripButton:NSButton {
    var moving=false
    var moveEnded: (() -> Void)?
    var resize:((CGSize,Bool)->Void)?
    override init(frame:NSRect) {super.init(frame:frame);isBordered=false;imagePosition = .imageOnly;bezelStyle = .regularSquare}
    convenience init(){self.init(frame:.zero)}
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    override var mouseDownCanMoveWindow:Bool {false}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    override func mouseDown(with event:NSEvent) {
        guard isEnabled,let window else{return}
        let frame=window.frame
        // Use the event's screen coordinates: synthesized input does not always
        // update NSEvent.mouseLocation, which previously yielded zero deltas.
        let start=window.convertPoint(toScreen:event.locationInWindow)
        while let next=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            let point=window.convertPoint(toScreen:next.locationInWindow)
            let ended=next.type == .leftMouseUp
            if moving {
                let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
                window.setFrameOrigin(NSPoint(x: frame.minX + delta.width, y: frame.minY + delta.height))
                if ended && hypot(delta.width, delta.height) >= 1 { moveEnded?() }
            } else {
                resize?(CGSize(width:point.x-start.x,height:start.y-point.y),ended)
            }
            if ended {break}
        }
    }
}
struct OverlayView: View {
    @ObservedObject var model: Model
    let toggleLock: () -> Void
    let chooseTheme: (String) -> Void
    let resize: (CGSize, Bool) -> Void
    let moveEnded: () -> Void
    var body: some View {
        GeometryReader { geo in
            let size=geo.size.width/OverlayGeometry.standard
            VStack(alignment:.leading,spacing:4*size) {
                HStack(spacing:4*size) {
                    WindowGrip(locked:model.locked,moving:true,moveEnded:moveEnded,resize:resize)
                        .frame(width:18*size,height:18*size)
                    Text(geo.size.width < 160 ? "Monitor" : "MonitorMac").font(.system(size:9*size,weight:.medium)).opacity(0.65)
                    Spacer(minLength:0)
                    Menu {
                        ForEach(Theme.all) { theme in Button(theme.title) { chooseTheme(theme.id) } }
                    } label: { Image(systemName:"paintpalette") }
                    .menuStyle(.borderlessButton).fixedSize().help("Overlay colors").accessibilityLabel("Overlay colors")
                    Button(action:toggleLock) { Image(systemName:model.locked ? "lock.fill" : "lock.open") }
                        .buttonStyle(.plain).frame(width:18*size,height:18*size)
                        .help(model.locked ? "Unlock position" : "Lock position")
                        .accessibilityLabel(model.locked ? "Unlock position" : "Lock position")
                }
                .font(.system(size:10*size)).frame(height:18*size)
                if MetricsReader.hasExperimentalSensors {
                    HStack(spacing:8*size) {
                        temperatureTile("CPU", cpu:true, size:size)
                        Rectangle().fill(Color(nsColor:model.theme.text).opacity(0.12)).frame(width:1,height:30*size)
                        temperatureTile("GPU", cpu:false, size:size)
                    }.frame(height:43*size)
                } else {
                    VStack(alignment: .leading, spacing: 2 * size) {
                        Text("THERMAL STATE")
                            .font(.system(size: 9 * size, weight: .medium)).opacity(0.65)
                        Text(model.snapshot.thermal)
                            .font(.system(size: 19 * size, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(nsColor: model.theme.accent))
                    }.frame(maxWidth: .infinity, minHeight: 43 * size, alignment: .leading)
                }
                Divider()
                HStack(alignment:.firstTextBaseline) {
                    Label("RAM",systemImage:"memorychip").font(.system(size:10*size,weight:.medium)).opacity(0.65)
                    Spacer(minLength:0)
                    Text(model.snapshot.percent.map{String(format:"%.0f%%",$0)} ?? "—")
                        .font(.system(size:22*size,weight:.semibold,design:.rounded)).monospacedDigit()
                }.frame(height:24*size)
                Text(model.memoryText + " · est.")
                    .font(.system(size:10*size,design:.monospaced)).opacity(0.6).lineLimit(1)
                    .frame(height:12*size)
                GeometryReader { bar in
                    Capsule().fill(Color(nsColor:model.theme.text).opacity(0.12))
                        .overlay(alignment:.leading) {
                            Capsule().fill(Color(nsColor:model.theme.accent))
                                .frame(width:bar.size.width * min(1,max(0,(model.snapshot.percent ?? 0)/100)))
                        }
                }.frame(height:3*size).accessibilityLabel("RAM usage")
                    .accessibilityValue(model.snapshot.percent.map{String(format:"%.0f percent",$0)} ?? "Unavailable")
                HStack(spacing:4*size) {
                    Circle().fill((MetricsReader.hasExperimentalSensors && model.stale) ? .orange : Color(nsColor:model.theme.accent)).frame(width:4*size,height:4*size)
                    Text(model.compactFooter).lineLimit(1).help(model.footer)
                    Spacer(minLength:0)
                    WindowGrip(locked:model.locked,moving:false,resize:resize)
                        .frame(width:16*size,height:16*size)
                }
                .font(.system(size:9*size)).opacity(0.7).frame(height:16*size)
            }
            .padding(10*size)
            .frame(width:geo.size.width,height:geo.size.height,alignment:.topLeading)
            .foregroundStyle(Color(nsColor:model.theme.text))
            .background(Color(nsColor:model.theme.background).opacity(model.opacity),in:RoundedRectangle(cornerRadius:20*size))
            .overlay(RoundedRectangle(cornerRadius:20*size).stroke(Color(nsColor:model.theme.text).opacity(0.14),lineWidth:1))
        }
        .preferredColorScheme(model.themeID == "light" ? .light : .dark)
        .environment(\.locale, interfaceLocale)
    }
    func temperatureTile(_ title:String, cpu:Bool, size:CGFloat) -> some View {
        VStack(alignment:.leading,spacing:2*size) {
            Text(title).font(.system(size:9*size,weight:.medium)).opacity(0.6)
            Text(model.temperature(cpu).map{String(format:"%.0f°",$0)} ?? "—")
                .font(.system(size:25*size,weight:.semibold,design:.rounded)).monospacedDigit()
                .foregroundStyle(Color(nsColor:model.theme.accent))
                .opacity(model.readings.isStale(model.reading(cpu),now:Date(),after:(UserDefaults.standard.object(forKey:"interval") as? Double ?? 2)*3) ? 0.55:1)
        }.frame(maxWidth:.infinity,alignment:.leading)
            .accessibilityElement(children:.ignore).accessibilityLabel(title)
            .accessibilityValue(model.tempText(cpu) + (model.readings.isStale(model.reading(cpu),now:Date(),after:(UserDefaults.standard.object(forKey:"interval") as? Double ?? 2)*3) ? ", stale or unavailable":""))
            .help("\(title): \(model.tempText(cpu))\n\(model.sourceText(cpu))\n\(model.footer)")
    }
}
final class OverlayPanel: NSPanel {
    // The explicit corner grip is the only drag resize path. Native border
    // resizing can change the frame independently of the grip's size limits.
    static let panelStyle: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    var buildContextMenu: (() -> NSMenu)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown, let contentView, let menu = buildContextMenu?() {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
            return
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class HostingView: NSHostingView<OverlayView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let model=Model(), defaults=UserDefaults.standard
    var panel:OverlayPanel!
    var item:NSStatusItem!
    var timer:Timer?
    private var hoverTimer: Timer?
    private var shortcut: GlobalShortcut?
    private var detailsWindow: NSWindow?
    private let history = MetricsHistory()
    private var pressureEvents: DispatchSourceMemoryPressure?
    private var notifiedPressure: MemoryPressure?
    var inFlight=false, sleeping=false, presented=false
    var generation=0
    var resizeStart:NSRect?
    var clickThrough=UserDefaults.standard.bool(forKey:"clickThrough")
    var rediscoverSensors=false
    let reader=MetricsReader()
    let queue=DispatchQueue(label:"MonitorMac.metrics",qos:.utility)
    var interval:Double { defaults.object(forKey:"interval") as? Double ?? 2 }
    var showNumbers:Bool { defaults.object(forKey:"showNumbers") as? Bool ?? true }
    var showOverlay:Bool { defaults.object(forKey:"showOverlay") as? Bool ?? true }
    var barColor:String { defaults.string(forKey:"barColor") ?? "system" }
    private var corner: OverlayCorner? {
        defaults.string(forKey: "overlayCorner").flatMap(OverlayCorner.init(rawValue:))
    }
    private var margin: CGFloat {
        defaults.object(forKey: "overlayMargin") as? CGFloat ?? 16
    }
    private var fadeNearPointer: Bool { defaults.bool(forKey: "fadeNearPointer") }
    private var shortcutEnabled: Bool { defaults.object(forKey: "globalShortcut") as? Bool ?? true }
    private var detailsVisible: Bool { detailsWindow?.isVisible == true }
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        let menu=NSMenu();menu.delegate=self;item.menu=menu
        let view = HostingView(rootView: OverlayView(
            model: model,
            toggleLock: { [weak self] in self?.toggleLock() },
            chooseTheme: { [weak self] in self?.applyTheme($0) },
            resize: { [weak self] in self?.resizeOverlay($0, ended: $1) },
            moveEnded: { [weak self] in self?.overlayDidDrag() }
        ))
        view.sizingOptions = []
        let width=OverlayGeometry.restoredWidth(defaults.object(forKey:"width") as? Double,layoutVersion:defaults.integer(forKey:"layoutVersion"))
        panel=OverlayPanel(contentRect:NSRect(x:0,y:0,width:width,height:OverlayGeometry.height(width)),styleMask:OverlayPanel.panelStyle,backing:.buffered,defer:false)
        panel.contentView=view;panel.isOpaque=false;panel.backgroundColor = .clear
        panel.isMovable = false
        panel.buildContextMenu = { [weak self] in
            let menu = NSMenu()
            self?.menuNeedsUpdate(menu)
            return menu
        }
        panel.minSize=NSSize(width:OverlayGeometry.minimum,height:OverlayGeometry.height(OverlayGeometry.minimum));panel.maxSize=NSSize(width:OverlayGeometry.maximum,height:OverlayGeometry.height(OverlayGeometry.maximum))
        panel.contentAspectRatio=NSSize(width:1,height:1)
        panel.hasShadow=true;panel.level = .floating;panel.hidesOnDeactivate=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.delegate=self
        panel.ignoresMouseEvents=clickThrough
        restorePosition()
        registerShortcut()
        observeMemoryPressure()
        menuNeedsUpdate(menu)
        defaults.set(width,forKey:"width");defaults.set(OverlayGeometry.layoutVersion,forKey:"layoutVersion")
        // Show available metrics after the first collection. A missing sensor
        // must not hide RAM or the other working temperature sensor.
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(willSleep),name:NSWorkspace.willSleepNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(didWake),name:NSWorkspace.didWakeNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(screensChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        updateStatus();schedule()
    }
    func schedule() {
        timer?.invalidate();timer=nil
        guard !sleeping,showNumbers || showOverlay || detailsVisible else{return}
        sample()
        let scheduled=Timer(timeInterval:interval,repeats:true){[weak self] _ in self?.sample()}
        scheduled.tolerance=interval*0.1
        RunLoop.main.add(scheduled,forMode:.common)
        timer=scheduled
    }
    func sample() {
        model.stale=model.readings.stale(now:Date(),after:interval*3)
        guard !inFlight,!sleeping else{return}
        inFlight=true;let current=generation
        let resetSensors=rediscoverSensors;rediscoverSensors=false
        queue.async { [weak self] in
            guard let self else{return}
            if resetSensors { self.reader.resetSensors() }
            let snapshot=self.reader.read()
            DispatchQueue.main.async {
                self.inFlight=false
                guard current==self.generation,!self.sleeping else{return}
                var sample = snapshot
                sample.memoryPressure = sample.memoryPressure ?? self.notifiedPressure
                self.model.snapshot = sample
                // Keep each last real reading through temporary sensor errors,
                // with a visible stale age rather than pretending it is live.
                self.model.readings.ingest(sample,cpuKey:self.model.cpuKey,gpuKey:self.model.gpuKey)
                let cpu = self.model.readings.cpu
                let gpu = self.model.readings.gpu
                self.history.append(HistorySample(date: sample.date,
                    cpu: cpu?.date == sample.date ? cpu?.sensor.celsius : nil,
                    gpu: gpu?.date == sample.date ? gpu?.sensor.celsius : nil,
                    ram: sample.percent))
                self.model.stale=self.model.readings.stale(now:Date(),after:self.interval*3)
                if !self.presented {
                    self.presented=true
                    if self.showOverlay { self.panel.orderFrontRegardless(); self.updateHoverTimer() }
                }
                self.updateStatus()
            }
        }
    }
    func updateStatus() {
        guard let button=item?.button else{return}
        button.attributedTitle=NSAttributedString(string:"")
        if showNumbers {
            button.image=nil
            let cpu = menuTemperature(cpu: true)
            let gpu = menuTemperature(cpu: false)
            let ram = model.snapshot.percent.map { String(format: "%.0f%%", $0) } ?? "—"
            let text = MetricsReader.hasExperimentalSensors ? "CPU \(cpu)  GPU \(gpu)  RAM \(ram)" : "Thermal \(model.snapshot.thermal)  RAM \(ram)"
            let color=barColor == "system" ? NSColor.labelColor : Theme.find(barColor).accent
            button.attributedTitle=NSAttributedString(string:text,attributes:[.foregroundColor:color,.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:.medium)])
        } else { button.title="";button.image=NSImage(systemSymbolName:"waveform.path.ecg",accessibilityDescription:"MonitorMac") }
        button.setAccessibilityLabel("MonitorMac — metrics and settings")
        button.toolTip=MetricsReader.hasExperimentalSensors ? "CPU: \(model.tempText(true)) [\(model.sourceText(true))]\nGPU: \(model.tempText(false)) [\(model.sourceText(false))]\nRAM: \(model.memoryText) (estimate)\n\(model.footer)\n\(model.snapshot.reason)" : "RAM: \(model.memoryText) (estimate)\n\(model.footer)"
    }
    private func menuTemperature(cpu: Bool) -> String {
        guard let reading = model.reading(cpu) else { return "—" }
        let old = model.readings.isStale(reading, now: Date(), after: interval * 3)
        return String(format: "%.0f°", reading.sensor.celsius) + (old ? "*" : "")
    }

    func menuNeedsUpdate(_ menu:NSMenu) {
        menu.autoenablesItems = false
        menu.removeAllItems();add(menu,"MonitorMac",nil).isEnabled=false
        add(menu,"Show overlay",#selector(toggleOverlay)).state=showOverlay ? .on:.off
        add(menu,"Menu bar metrics",#selector(toggleNumbers)).state=showNumbers ? .on:.off
        add(menu,"Lock position",#selector(toggleLock)).state=model.locked ? .on:.off
        add(menu,"Click through overlay (access apps behind it)",#selector(toggleClickThrough)).state=clickThrough ? .on:.off
        add(menu,"Fade overlay near pointer",#selector(toggleHoverFade)).state = fadeNearPointer ? .on : .off
        let shortcutTitle = shortcutEnabled && shortcut == nil ? "Retry global shortcut (⌃⇧⌘M)" : "Global shortcut (⌃⇧⌘M)"
        add(menu,shortcutTitle,#selector(toggleShortcut)).state = shortcut != nil ? .on : .off
        add(menu,"Details and history…",#selector(showDetails))
        addPlacementMenu(to: menu)
        addLoginItem(to: menu)
        if MetricsReader.hasExperimentalSensors { add(menu,"Retry sensors now",#selector(retry)) }
        let colors=NSMenu();add(menu,"Overlay colors",nil).submenu=colors
        for theme in Theme.all {let row=add(colors,theme.title,#selector(setTheme));row.representedObject=theme.id;row.state=theme.id==model.themeID ? .on:.off}
        let bar=NSMenu();add(menu,"Menu bar colors",nil).submenu=bar
        let system=add(bar,"System (automatic contrast)",#selector(setBarColor));system.representedObject="system";system.state=barColor=="system" ? .on:.off
        for theme in Theme.all.filter({$0.id != "light"}) {let row=add(bar,theme.title,#selector(setBarColor));row.representedObject=theme.id;row.state=barColor==theme.id ? .on:.off}
        let sizes=NSMenu();sizes.autoenablesItems=false;add(menu,"Overlay size",nil).submenu=sizes
        for (title,width) in [("Mini · 144 × 144",144.0),("Standard · 164 × 164",164.0),("Large · 184 × 184",184.0),("Maximum · 200 × 200",200.0)] {let row=add(sizes,title,#selector(setSize));row.representedObject=width;row.isEnabled = !model.locked;row.state=abs(panel.frame.width-width)<0.5 ? .on:.off}
        menu.addItem(.separator())
        if MetricsReader.hasExperimentalSensors {
            for cpu in [true,false] {
                let sub=NSMenu();add(menu,cpu ? "CPU sensor":"GPU sensor",nil).submenu=sub
                let key=cpu ? model.cpuKey:model.gpuKey
                let auto=add(sub,"Automatic Apple Silicon (group maximum)",#selector(selectSensor));auto.representedObject=[cpu ? "cpuKey":"gpuKey","auto"];auto.state=key=="auto" ? .on:.off
                for sensor in model.snapshot.sensors.sorted(by:{$0.name<$1.name}) {let row=add(sub,String(format:"%@ — %.1f °C",sensor.name,sensor.celsius),#selector(selectSensor));row.representedObject=[cpu ? "cpuKey":"gpuKey",sensor.name];row.state=key==sensor.name ? .on:.off}
            }
        }
        let intervals=NSMenu();add(menu,"Update interval",nil).submenu=intervals
        for seconds in [1.0, 2, 5] {
            let title = seconds == 1 ? "Every second" : "Every \(Int(seconds)) seconds"
            let row = add(intervals, title, #selector(setInterval))
            row.representedObject = seconds
            row.state = seconds == interval ? .on : .off
        }
        let opacity=NSMenu();add(menu,"Opacity",nil).submenu=opacity
        for value in [0.5,0.75,0.9,1] {let row=add(opacity,"\(Int(value*100))%",#selector(setOpacity));row.representedObject=value;row.state=value==model.opacity ? .on:.off}
        menu.addItem(.separator());add(menu,"Diagnostics…",#selector(diagnostics));add(menu,"Quit MonitorMac",#selector(quit)).keyEquivalent="q"
    }
    @discardableResult func add(_ menu:NSMenu,_ title:String,_ action:Selector?) -> NSMenuItem {let row=NSMenuItem(title:title,action:action,keyEquivalent:"");row.target=self;menu.addItem(row);return row}
    @objc func toggleOverlay() {
        let visible = !showOverlay
        defaults.set(visible, forKey: "showOverlay")
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        updateHoverTimer()
        schedule()
    }
    @objc func toggleNumbers(){defaults.set(!showNumbers,forKey:"showNumbers");updateStatus();schedule()}
    @objc func toggleLock() {
        model.locked.toggle()
        defaults.set(model.locked, forKey: "locked")
        resizeStart = nil
    }
    @objc func toggleClickThrough(){clickThrough.toggle();panel.ignoresMouseEvents=clickThrough;defaults.set(clickThrough,forKey:"clickThrough")}
    func applyTheme(_ id:String){model.themeID=id;defaults.set(id,forKey:"theme")}
    @objc func setTheme(_ sender:NSMenuItem){if let id=sender.representedObject as? String{applyTheme(id)}}
    @objc func setBarColor(_ sender:NSMenuItem){if let id=sender.representedObject as? String{defaults.set(id,forKey:"barColor");updateStatus()}}
    func resizeOverlay(_ delta:CGSize,ended:Bool){
        guard !model.locked else{return}
        if resizeStart==nil {resizeStart=panel.frame}
        let start=resizeStart!;let change=abs(delta.width)>abs(delta.height) ? delta.width:delta.height
        setWidth(start.width+change,anchor:start)
        if ended {
            resizeStart = nil
            applyPlacement()
        }
    }
    func setWidth(_ value: CGFloat, anchor: NSRect? = nil) {
        let frame = OverlayGeometry.resizedFrame(from: anchor ?? panel.frame, proposedSide: value)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
        defaults.set(frame.width, forKey: "width")
    }
    @objc func setSize(_ sender: NSMenuItem) {
        guard !model.locked, let side = sender.representedObject as? Double else { return }
        setWidth(side)
        applyPlacement()
    }
    @objc func selectSensor(_ sender:NSMenuItem){guard let args=sender.representedObject as? [String] else{return};defaults.set(args[1],forKey:args[0]);if args[0]=="cpuKey"{model.cpuKey=args[1];model.readings.cpu=nil}else{model.gpuKey=args[1];model.readings.gpu=nil};sample()}
    @objc func retry(){rediscoverSensors=true;sample()}
    @objc func setInterval(_ sender:NSMenuItem){guard let v=sender.representedObject as? Double else{return};defaults.set(v,forKey:"interval");schedule()}
    @objc func setOpacity(_ sender:NSMenuItem){guard let v=sender.representedObject as? Double else{return};defaults.set(v,forKey:"opacity");model.opacity=v}
    @objc func willSleep() {
        sleeping = true
        generation += 1
        timer?.invalidate()
        timer = nil
        updateHoverTimer()
        model.readings.requireFreshReadings(after: Date())
        model.stale = true
        updateStatus()
    }

    @objc func didWake() {
        sleeping = false
        generation += 1
        model.readings.requireFreshReadings(after: Date())
        rediscoverSensors = true
        model.stale = true
        applyPlacement()
        updateHoverTimer()
        schedule()
    }

    @objc func screensChanged() { applyPlacement() }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        defaults.set(panel.frame.minX, forKey: "x")
        defaults.set(panel.frame.minY, forKey: "y")
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === detailsWindow {
            detailsWindow = nil
            schedule()
        }
    }

    private func restorePosition() {
        if defaults.object(forKey: "x") != nil {
            panel.setFrameOrigin(NSPoint(x: defaults.double(forKey: "x"),
                                         y: defaults.double(forKey: "y")))
        } else {
            defaults.set(OverlayCorner.topRight.rawValue, forKey: "overlayCorner")
        }
        applyPlacement()
    }

    private func availableScreen() -> NSScreen? {
        let preferred = defaults.string(forKey: "overlayDisplay")
        return NSScreen.screens.first { displayIdentifier($0) == preferred }
            ?? panel.screen ?? NSScreen.screens.first
    }

    private func displayIdentifier(_ screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let display = CGDirectDisplayID(number.uint32Value)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return number.stringValue
    }

    private func applyPlacement() {
        if let corner, let screen = availableScreen() {
            panel.setFrameOrigin(corner.origin(in: screen.visibleFrame, side: panel.frame.width, margin: margin))
            return
        }
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }),
              let screen = availableScreen() else { return }
        let area = screen.visibleFrame
        let x = min(max(panel.frame.minX, area.minX), max(area.minX, area.maxX - panel.frame.width))
        let y = min(max(panel.frame.minY, area.minY), max(area.minY, area.maxY - panel.frame.height))
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func overlayDidDrag() {
        defaults.removeObject(forKey: "overlayCorner")
        defaults.removeObject(forKey: "overlayDisplay")
        if let screen = panel.screen {
            let origin = panel.frame.origin
            let nearCorner = OverlayCorner.allCases.first {
                let cornerOrigin = $0.origin(in: screen.visibleFrame, side: panel.frame.width, margin: margin)
                return hypot(cornerOrigin.x - origin.x, cornerOrigin.y - origin.y) <= 20
            }
            if let nearCorner {
                defaults.set(nearCorner.rawValue, forKey: "overlayCorner")
                defaults.set(displayIdentifier(screen), forKey: "overlayDisplay")
            }
        }
        applyPlacement()
    }

    private func addPlacementMenu(to menu: NSMenu) {
        let position = NSMenu()
        add(menu,"Overlay position",nil).submenu = position
        let currentDisplay = defaults.string(forKey: "overlayDisplay")
        let displayMenu = NSMenu()
        add(position,"Display",nil).submenu = displayMenu
        let automatic = add(displayMenu,"Current display",#selector(setDisplay))
        automatic.state = currentDisplay == nil ? .on : .off
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let id = displayIdentifier(screen) else { continue }
            let row = add(displayMenu,"\(index + 1) · \(screen.localizedName)",#selector(setDisplay))
            row.representedObject = id
            row.state = currentDisplay == id ? .on : .off
        }
        let corners = NSMenu()
        add(position,"Corner",nil).submenu = corners
        add(corners,"Free position",#selector(setCorner)).state = corner == nil ? .on : .off
        for choice in OverlayCorner.allCases {
            let row = add(corners,choice.rawValue,#selector(setCorner))
            row.representedObject = choice.rawValue
            row.state = choice == corner ? .on : .off
        }
        let margins = NSMenu()
        margins.autoenablesItems = false
        add(position,"Margin",nil).submenu = margins
        for points in [0, 8, 16, 24, 32] {
            let row = add(margins,"\(points) pt",#selector(setMargin))
            row.representedObject = points
            row.state = CGFloat(points) == margin ? .on : .off
            row.isEnabled = corner != nil
        }
    }

    @objc private func setDisplay(_ sender: NSMenuItem) {
        let selected = sender.representedObject as? String
        defaults.set(selected, forKey: "overlayDisplay")
        if selected != nil && corner == nil {
            defaults.set(OverlayCorner.topRight.rawValue, forKey: "overlayCorner")
        }
        applyPlacement()
    }

    @objc private func setCorner(_ sender: NSMenuItem) {
        let selected = sender.representedObject as? String
        defaults.set(selected, forKey: "overlayCorner")
        if selected == nil { defaults.removeObject(forKey: "overlayDisplay") }
        applyPlacement()
    }

    @objc private func setMargin(_ sender: NSMenuItem) {
        guard let points = sender.representedObject as? Int else { return }
        defaults.set(points, forKey: "overlayMargin")
        applyPlacement()
    }

    @objc private func toggleHoverFade() {
        defaults.set(!fadeNearPointer, forKey: "fadeNearPointer")
        updateHoverTimer()
    }

    private func updateHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        guard fadeNearPointer, panel.isVisible, !sleeping else {
            panel.alphaValue = 1
            return
        }
        updateHover()
        let timer = Timer(timeInterval: 0.16, repeats: true) { [weak self] _ in
            self?.updateHover()
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func updateHover() {
        let nearby = panel.frame.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation)
        let opacity: CGFloat = nearby ? 0.28 : 1
        if panel.alphaValue != opacity { panel.alphaValue = opacity }
    }

    private func registerShortcut() {
        shortcut = shortcutEnabled ? GlobalShortcut { [weak self] in self?.toggleOverlay() } : nil
    }

    @objc private func toggleShortcut() {
        defaults.set(shortcut == nil, forKey: "globalShortcut")
        registerShortcut()
    }

    @objc private func showDetails() {
        if detailsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 495, height: 425),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "MonitorMac Details"
            window.contentView = NSHostingView(rootView: MetricsDetails(model: model, history: history)
                .environment(\.locale, interfaceLocale))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            detailsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        detailsWindow?.makeKeyAndOrderFront(nil)
        schedule()
    }

    private func observeMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, let events = self.pressureEvents?.data else { return }
            if events.contains(.critical) { self.notifiedPressure = .critical }
            else if events.contains(.warning) { self.notifiedPressure = .warning }
            else if events.contains(.normal) { self.notifiedPressure = .normal }
        }
        pressureEvents = source
        source.activate()
    }

    private func addLoginItem(to menu: NSMenu) {
        let status = SMAppService.mainApp.status
        let row = add(menu, "Open at login", #selector(toggleLogin))
        row.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
        if status == .requiresApproval {
            add(menu, "Review login item in System Settings…", #selector(openLoginSettings))
        }
    }

    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        let isRegistered = service.status == .enabled || service.status == .requiresApproval
        let location = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        if !isRegistered && (location.hasPrefix("/private/tmp/") || location.hasPrefix("/private/var/folders/")) {
            showMessage("Move MonitorMac before enabling launch at login",
                        "Extract MonitorMac.app from the ZIP, move it to Applications, and open that copy.")
            return
        }
        do {
            if isRegistered { try service.unregister() } else { try service.register() }
            if service.status == .requiresApproval {
                showMessage("Approve MonitorMac in System Settings",
                            "Open Login Items & Extensions and allow MonitorMac to open at login.")
            }
        } catch {
            showMessage("Could not update launch at login", error.localizedDescription)
        }
    }

    private func showMessage(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func diagnostics() {
        let alert = NSAlert()
        alert.messageText = "MonitorMac Diagnostics"
        var lines = [
            "macOS " + ProcessInfo.processInfo.operatingSystemVersionString,
            model.snapshot.reason,
            "RAM: " + model.memoryText + " (estimate)",
            model.footer
        ]
        if MetricsReader.hasExperimentalSensors {
            lines.append("CPU: " + model.sourceText(true))
            lines.append("GPU: " + model.sourceText(false))
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc func quit(){NSApp.terminate(nil)}
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        hoverTimer?.invalidate()
        shortcut = nil
        pressureEvents?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
@main struct MonitorMacMain {
    static func main(){if CommandLine.arguments.contains("--diagnose"){let s=MetricsReader().read();print(s.reason);for sensor in s.sensors{print("\(sensor.name): \(sensor.celsius) °C")};return};let app=NSApplication.shared;let delegate=AppDelegate();app.delegate=delegate;withExtendedLifetime(delegate){app.run()}}
}
