import AppKit

final class AppearanceSettingsPage {
    private let form:SettingsForm
    private unowned let window:NSWindow
    private let reload:() -> Void, onPreviewDetails:() -> Void
    private var preferences:PetPreferences {form.preferences}
    private var materialPreview: Bubble?
    private var previewDismissal: DispatchWorkItem?
    private weak var glassSlider: GlassOpacitySlider?
    private weak var glassFollowSwitch: NSSwitch?
    private var glassControls = [NSView]()
    private var accentButtons = [NSButton]()
    private var accentNames = [NSTextField]()
    init(form:SettingsForm,window:NSWindow,reload:@escaping () -> Void,onPreviewDetails:@escaping () -> Void) {
        self.form = form; self.window = window; self.reload = reload; self.onPreviewDetails = onPreviewDetails
    }
    func reset() {dismissPreview(); accentButtons.removeAll(); accentNames.removeAll(); glassControls.removeAll()}
    func refreshAvailability() {
        glassSlider?.isEnabled = !preferences.bool("glassFollowsSystem")
        glassFollowSwitch?.state = preferences.bool("glassFollowsSystem") ? .on : .off
        for view in glassControls {view.alphaValue = preferences.bool("glassFollowsSystem") ? 0.45 : 1}
    }
    func refreshAccent() {
        for (index,button) in accentButtons.enumerated() {
            let chosen = AppAccent.choices[index].0 == preferences.string("accentStyle")
            button.state = chosen ? .on : .off; button.needsDisplay = true
            accentNames[index].stringValue = chosen ? AppAccent.choices[index].1 : ""
        }
    }
    func render() {
        form.group("Size",[form.slider("Pet size","petPercent",range:50...200,suffix:"%"),form.slider("Bubble size","bubblePercent",range:50...150,suffix:"%"),form.slider("Message font size","messageFontSize",range:11...20,suffix:"pt")])
        form.group("Pet outline",[form.toggle("Outline shadow","petShadow",detail:"Show a soft shadow around the pet.")])
        form.group("Bubble shape",[form.toggle("Custom aspect ratio","bubbleAspectEnabled"),form.slider("Width : Height","bubbleAspectRatio",range:0.6...3,step:0.1,suffix:": 1",requires:["bubbleAspectEnabled"])])
        let palette = NSStackView(); palette.spacing = 3; palette.alignment = .top
        for (key,name) in AppAccent.choices {
            let dot = AccentSwatch(key:key,name:name)
            dot.state = preferences.string("accentStyle") == key ? .on : .off
            form.attach(dot) { [weak self] _ in
                guard let self else {return}
                self.preferences.set(key,for:"accentStyle")
                self.reload()
            }
            let caption = NSTextField(labelWithString:dot.state == .on ? name : "")
            caption.font = .systemFont(ofSize:9); caption.textColor = .secondaryLabelColor; caption.alignment = .center
            caption.heightAnchor.constraint(equalToConstant:13).isActive = true
            let column = NSStackView(views:[dot,caption]); column.orientation = .vertical; column.spacing = 2
            column.widthAnchor.constraint(equalToConstant:38).isActive = true
            caption.widthAnchor.constraint(equalTo:column.widthAnchor).isActive = true
            palette.addArrangedSubview(column); accentButtons.append(dot); accentNames.append(caption)
        }
        var themeRows = [form.segmented("Appearance mode","appearanceMode",AppAppearance.choices,symbols:["system":"circle.lefthalf.filled","light":"sun.max","dark":"moon"]),form.row("Accent color",control:palette)]
        if preferences.string("accentStyle") == "custom" {
            let well = CenteredColorWell(); well.color = AppAccent.color; well.widthAnchor.constraint(equalToConstant:70).isActive = true
            form.attach(well) { [weak self] sender in guard let rgb = (sender as! NSColorWell).color.usingColorSpace(.sRGB) else {return}; self?.preferences.set([rgb.redComponent,rgb.greenComponent,rgb.blueComponent],for:"accentRGB") }
            themeRows.append(form.row("Custom",control:well))
        }
        form.group("Theme",themeRows)
        let material = form.segmented("Message window material","bubbleMaterial",[("glass","Liquid Glass"),("plain","Plain")],value:preferences.usesGlass ? "glass" : "plain",enabled:PetPreferences.glassAvailable,detail:"Liquid Glass requires macOS 26 or later.") { [weak self] in self?.reload(); self?.showPreview() }
        var materialRows = [material]
        if preferences.usesGlass {
            let follow = AccentSwitch(); follow.state = preferences.bool("glassFollowsSystem") ? .on : .off; glassFollowSwitch = follow
            follow.setAccessibilityLabel("Use system Liquid Glass settings")
            form.attach(follow) { [weak self] sender in self?.preferences.set((sender as! NSSwitch).state == .on,for:"glassFollowsSystem"); self?.showPreview() }
            materialRows.append(form.row("Use system Liquid Glass settings",control:follow))
            let slider = GlassOpacitySlider(); slider.minValue = 0; slider.maxValue = 1; slider.doubleValue = preferences.number("glassOpacity")
            slider.numberOfTickMarks = 5; slider.allowsTickMarkValuesOnly = false; slider.isContinuous = true
            slider.trackFillColor = AppAccent.color; slider.widthAnchor.constraint(equalToConstant:180).isActive = true
            slider.setAccessibilityLabel("Glass opacity"); slider.isEnabled = !preferences.bool("glassFollowsSystem"); glassSlider = slider
            form.attach(slider) { [weak self] sender in self?.preferences.set((sender as! NSSlider).doubleValue,for:"glassOpacity"); self?.showPreview() }
            slider.ended = { [weak self] in self?.schedulePreviewDismissal() }
            let left = glassSymbol(filled:false), right = glassSymbol(filled:true)
            let controls = NSStackView(views:[left,slider,right]); controls.spacing = 8; controls.alignment = .centerY
            controls.widthAnchor.constraint(equalToConstant:244).isActive = true
            controls.alphaValue = slider.isEnabled ? 1 : 0.45; glassControls = [controls]
            materialRows.append(form.row("Glass opacity",control:controls))
        }
        materialRows.append(form.toggle("Motion effects","bubbleMotion"))
        materialRows.append(form.row("Bubble effects",control:ActionButton("Preview Bubble") { [weak self] in self?.showPreview() }))
        form.group("Message windows",materialRows)
    }
    private func glassSymbol(filled:Bool) -> NSImageView {
        let name = "capsule.on.rectangle.liquid.glass" + (filled ? ".fill" : "")
        let image = NSImage(systemSymbolName:name,accessibilityDescription:nil) ?? NSImage(contentsOf:Paths.resources.appendingPathComponent("glass-symbols/"+name+".pdf"))
        image?.isTemplate = true
        let view = NSImageView(); view.image = image; view.contentTintColor = .secondaryLabelColor
        view.setAccessibilityLabel(filled ? "More opaque" : "More transparent")
        view.widthAnchor.constraint(equalToConstant:24).isActive = true; view.heightAnchor.constraint(equalToConstant:24).isActive = true
        return view
    }
    func showPreview() {
        previewDismissal?.cancel()
        if materialPreview == nil {materialPreview = Bubble(); materialPreview?.onDetails = { [weak self] in self?.onPreviewDetails() }}
        guard let preview = materialPreview else {return}
        if !preview.visible {preview.show(title:preferences.petName,body:preferences.statusLine("greetingTemplate"),kind:"preview",scale:preferences.number("bubblePercent")/100,seconds:0,details:true)}
        guard let screen = window.screen ?? NSScreen.main else {return}
        let visible = screen.visibleFrame, size = preview.targetFrame.size
        let x = min(visible.maxX-size.width-12,max(visible.minX+12,window.frame.maxX+12))
        let y = min(visible.maxY-size.height-12,max(visible.minY+12,window.frame.maxY-size.height-72))
        preview.move(to:NSPoint(x:x,y:y))
        if glassSlider?.tracking != true {schedulePreviewDismissal()}
    }
    private func schedulePreviewDismissal() {
        previewDismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.materialPreview?.hide() }
        previewDismissal = work; DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:work)
    }
    func dismissPreview() {previewDismissal?.cancel(); previewDismissal = nil; materialPreview?.hide()}
    deinit {previewDismissal?.cancel()}
}
