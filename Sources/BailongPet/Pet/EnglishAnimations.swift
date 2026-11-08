import Foundation

// Keep asset identifiers and filenames unchanged so upstream HEVC packs remain compatible.
enum EnglishAnimations {
    static let introduction = "Hi! I'm Bailong (白龙), a fan-made chibi dragon girl inspired by ChatGPT! My hairpin and belt bear OpenAI logos. 🐉"
    static let titles: [String: String] = [
        "idle": "Default Idle", "idle2": "Idle 02",
        "idle03": "Reading a Picture Book", "idle04": "Hugging a Pillow",
        "idle05": "Playing a Handheld Game", "idle06": "Cuddling My Tail",
        "drag": "Drag", "landing": "Landing", "quota": "Check Usage",
        "move02": "Run Right", "move02left": "Run Left",
        "move01left": "Walk Left", "move01right": "Walk Right",
        "move03left": "Fly Left", "move03right": "Fly Right",
        "01": "Introduce Myself", "04": "Inspiration", "05": "Feeling Proud",
        "08": "Dragon Hug", "09": "Playing It Cool", "13": "A Little Grumpy",
        "14": "Sleepy", "17": "Sneaking a Snack", "18": "Celebration",
        "20": "Sending Love", "21": "Dragon Pact", "22": "Our Bond",
        "24": "Treasure Collection", "25": "Little Dragon Breath", "26": "Trust",
        "work01": "Task Received", "work02": "Working on a Task",
        "work03": "Organizing Files", "work04": "Reading Reference Material",
        "work05": "Inspecting the Details"
    ]
    static let lines: [String: String] = [
        "01": introduction,
        "04": "Ding! {userName}, I just caught a brilliant little idea!",
        "05": "Hehe, {userName}, I solved that one!",
        "08": "A tiny dragon hug for you, {userName}.",
        "09": "I wasn't waiting for you, {userName}… well, maybe just a little.",
        "13": "Don't worry, {userName}! I'll break this tricky problem into tiny pieces!",
        "14": "Yaaawn… may I take a little nap on your desk, {userName}?",
        "17": "This cookie, {userName}… is fuel for thinking!",
        "18": "All done! A little gold star for each of us, {userName}!",
        "20": "Today's little dose of love has arrived on your desktop, {userName}.",
        "21": "By my horns and wings, I promise to be your little dragon companion, {userName}.",
        "22": "Our bond is glowing! I'll be your dragon companion from now on, {userName}.",
        "24": "Coins, gems, and you, {userName}… all my favorite treasures!",
        "25": "Fwoosh! Tiny dragon breath! Only for roasting marshmallows, {userName}.",
        "26": "Only you may touch this special scale. Be gentle, {userName}.",
        "work01": "Got it, {userName}! Let me carefully write down your instructions.",
        "work02": "{userName}, the code is lining up neatly beneath my little paws.",
        "work03": "Everything is filed away, {userName}. Much easier to find now!",
        "work04": "Let me check my references, {userName}. A good answer is hiding in these pages.",
        "work05": "Let me look closely, {userName}. No tiny detail escapes a dragon girl's eyes!"
    ]
}
