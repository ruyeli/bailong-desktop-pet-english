import AppKit

final class ActivitySettingsPage {
    private let form:SettingsForm, catalog:Catalog?
    private let reload:() -> Void, onPreview:(Clip) -> Void
    private var preferences:PetPreferences {form.preferences}
    init(form:SettingsForm,catalog:Catalog?,reload:@escaping () -> Void,onPreview:@escaping (Clip) -> Void) {
        self.form = form; self.catalog = catalog; self.reload = reload; self.onPreview = onPreview
    }
    func render() {
        let actions = [("none","No action"),("chat","Quick Chat"),("quota","Check Usage"),("history","View History"),("random","Progress & random animation")]
        form.group("Mouse interaction",[form.choice("Single-click pet","singleClickAction",actions),form.choice("Double-click pet","doubleClickAction",actions),form.choice("Double right-click pet","rightDoubleClickAction",actions)])
        let interval = preferences.number("leisureInterval")
        let preset = interval == 60 ? "60" : interval == 15 ? "15" : interval == 8 ? "8" : "custom"
        form.group("Autonomous activity",[
            form.popup("Activity level",options:[("60","Quiet"),("15","Moderate"),("8","Lively"),("custom","Custom")],value:preset) { [weak self] value in if let seconds = Double(value) {self?.preferences.set(seconds,for:"leisureInterval"); self?.reload()} },
            form.slider("Activity interval","leisureInterval",range:5...180,suffix:"seconds",detail:"After this interval, switch when the current animation finishes."),
            form.toggle("Autonomous movement","autoMove"),form.choice("Movement range","movementRange",[("still","Stay in place"),("nearby","Nearby"),("screen","Entire screen")],requires:["autoMove"]),form.toggle("Reduce repeated animations","avoidRepeat",detail:"Applies to random interactions, extra activities, and movement. Tasks exclude the previous animation; idle and docked animations use their own frequencies."),
            form.slider("Overall playback speed","playbackSpeed",range:0.75...1.5,step:0.05,suffix:"×",detail:"Animation and movement share a timeline. Per-animation speed multiplies the overall speed.")])
        form.group("Task animations",[form.toggle("Play task opening animation","taskOpening"),form.toggle("Celebrate completed tasks","taskCelebration")])
        guard let catalog else {return}
        for (title,clips,automatic) in [("Idle animations",catalog.idles+catalog.extras,true),("Interaction animations",catalog.variants,true),("Work animations",catalog.work,true),("Movement animations",catalog.movementAnimations,true),("Mouse & usage animations",[catalog.dragAnimation,catalog.landingAnimation,catalog.quotaAnimation],false)] {
            form.group(title,clips.map {clip in animationRow(clip,automatic:automatic)})
        }
        form.fill(form.note("Default idle weights are 4:1, or 7:3 when docked. During tasks, work/idle groups use 35:65 weights, excluding the previous animation; choices within each group are uniform. Frequency and favorites adjust these weights. Explicit previews, dragging, landing, usage checks, and task events ignore random frequency. Default idle remains available."),in:form.content)
    }
    private func animationRow(_ clip: Clip, automatic: Bool) -> NSView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        let controls = NSStackView(); controls.spacing = 8
        let preview = ActionButton("Play") { [weak self] in self?.onPreview(clip) }; preview.image = NSImage(systemSymbolName:"play.fill",accessibilityDescription:nil); preview.imagePosition = .imageLeading
        if automatic {
            let star = AccentChoiceButton(title:"Favorite",type:.switch); star.state = preferences.favorites.contains(clip.id) ? .on : .off
            form.attach(star) { [weak self] sender in guard let self else {return}; var values = self.preferences.favorites.filter {$0 != clip.id}; if (sender as! NSButton).state == .on {values.append(clip.id)}; self.preferences.set(values,for:"favorites") }
            controls.addArrangedSubview(star)
            let menu = NSPopUpButton(); let values = clip.id == "idle" ? [1,3,4,6] : [0,1,3,4,6]
            let names = [0:"Close",1:"Rare",3:"Occasional",4:"Often",6:"Frequent"]
            menu.addItems(withTitles:values.map {names[$0]!}); menu.selectItem(at:values.firstIndex(of:preferences.baseWeight(clip.id)) ?? 0)
            menu.setAccessibilityLabel(clip.title+" frequency")
            form.attach(menu) { [weak self] sender in self?.preferences.setWeight(values[(sender as! NSPopUpButton).indexOfSelectedItem],for:clip.id) }
            controls.addArrangedSubview(menu)
        }
        controls.addArrangedSubview(preview)
        let image = NSImageView(); image.image = NSImage(systemSymbolName:"film",accessibilityDescription:nil); image.contentTintColor = .secondaryLabelColor
        image.widthAnchor.constraint(equalToConstant:20).isActive = true; image.heightAnchor.constraint(equalToConstant:20).isActive = true
        let name = label(clip.title); let nameStack = NSStackView(views:[image,name]); nameStack.spacing = 8
        form.fill(form.alignedRow(leading:nameStack,control:controls),in:stack)
        let options = [("0.75","0.75×"),("1.0","1× (default)"),("1.25","1.25×"),("1.5","1.5×")]
        form.fill(form.popup("Animation speed",options:options,value:String(preferences.clipSpeed(clip.id))) { [weak self] in self?.preferences.setSpeed(Double($0)!,for:clip.id) },in:stack)
        return form.searchable(stack,title:clip.title)
    }
}
