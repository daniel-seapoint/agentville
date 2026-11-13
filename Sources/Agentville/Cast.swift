import Foundation

/// A named character from a film or TV world, dressed for the part.
struct CastMember: Identifiable, Hashable {
    let id: String
    let name: String
    let look: PixelArt.Look
}

/// The characters each film, TV or seasonal theme can cast its agents as. Each theme's main characters
/// are each played by one agent at a time, so there is only ever one wizard; when there are
/// more agents than characters, the rest play extras.
enum Cast {
    /// The cast a theme draws on. Both Lord of the Rings scenes share one.
    static func key(for theme: Theme) -> String? {
        if theme.isMiddleEarth { return "middleEarth" }
        if theme == .harryPotter { return "harryPotter" }
        if theme == .simpsons { return "simpsons" }
        if theme == .starWars { return "starWars" }
        if theme == .santaClaude { return "northPole" }
        return nil
    }

    static func main(_ key: String) -> [CastMember] {
        typealias Look = PixelArt.Look
        switch key {
        case "middleEarth":
            return [
                CastMember(id: "gandalf", name: "Gandalf",
                           look: Look(hat: .greyWizard, accessories: [.longBeard], pattern: .greyRobe, cape: "h", held: .staff)),
                CastMember(id: "aragorn", name: "Aragorn",
                           look: Look(hat: .longHair, accessories: [.mustache], pattern: .tunic, cape: "g", held: .sword, hair: "k")),
                CastMember(id: "legolas", name: "Legolas",
                           look: Look(hat: .longHair, pattern: .tunic, held: .longbow, hair: "y")),
                CastMember(id: "gimli", name: "Gimli",
                           look: Look(hat: .ironHelmet, accessories: [.bushyBeard], pattern: .chainmail, held: .axe, beard: "x")),
                CastMember(id: "frodo", name: "Frodo",
                           look: Look(hat: .curlyHair, pattern: .waistcoat, cape: "h", held: .sword, hair: "k")),
                CastMember(id: "sam", name: "Sam",
                           look: Look(hat: .curlyHair, pattern: .waistcoat, hair: "O")),
                CastMember(id: "merry", name: "Merry",
                           look: Look(hat: .curlyHair, pattern: .waistcoat, cape: "g", hair: "o")),
                CastMember(id: "pippin", name: "Pippin",
                           look: Look(hat: .curlyHair, pattern: .waistcoat, hair: "x")),
                CastMember(id: "boromir", name: "Boromir",
                           look: Look(hat: .longHair, accessories: [.mustache], pattern: .chainmail, cape: "R", held: .sword, hair: "o")),
            ]
        case "harryPotter":
            return [
                CastMember(id: "dumbledore", name: "Dumbledore",
                           look: Look(hat: .greyWizard, accessories: [.longBeard], pattern: .greyRobe, cape: "h", held: .wand)),
                CastMember(id: "harry", name: "Harry",
                           look: Look(hat: .messyHair, accessories: [.roundGlasses, .stripedScarf], pattern: .schoolRobe,
                                      cape: "H", held: .wand, hair: "j")),
                CastMember(id: "ron", name: "Ron",
                           look: Look(hat: .messyHair, accessories: [.stripedScarf], pattern: .schoolRobe, held: .wand, hair: "x")),
                CastMember(id: "hermione", name: "Hermione",
                           look: Look(hat: .curlyHair, accessories: [.stripedScarf], pattern: .schoolRobe, held: .wand, hair: "o")),
                CastMember(id: "hagrid", name: "Hagrid",
                           look: Look(hat: .messyHair, accessories: [.bushyBeard], pattern: .robe, held: .umbrella,
                                      hair: "j", beard: "k")),
                CastMember(id: "snape", name: "Snape",
                           look: Look(hat: .longHair, pattern: .schoolRobe, cape: "H", held: .wand, hair: "j")),
                CastMember(id: "neville", name: "Neville",
                           look: Look(hat: .messyHair, pattern: .schoolRobe, held: .wand, hair: "k")),
                CastMember(id: "luna", name: "Luna",
                           look: Look(hat: .longHair, pattern: .schoolRobe, held: .wand, hair: "y")),
                CastMember(id: "draco", name: "Draco",
                           look: Look(hat: .spikyHair, pattern: .schoolRobe, cape: "H", held: .wand, hair: "y")),
            ]
        case "simpsons":
            // On this theme every agent is drawn with yellow cartoon skin, so these are all
            // about hair and clothes.
            return [
                CastMember(id: "homer", name: "Homer",
                           look: Look(hat: .twoHairs, pattern: .shirt, held: .donut)),
                CastMember(id: "marge", name: "Marge",
                           look: Look(hat: .beehive, accessories: [.pearls], pattern: .greenDress)),
                CastMember(id: "bart", name: "Bart",
                           look: Look(hat: .spikyHair, pattern: .redShirt, hair: "T")),
                CastMember(id: "lisa", name: "Lisa",
                           look: Look(hat: .spikyHair, accessories: [.pearls], pattern: .redDress, hair: "T")),
                CastMember(id: "maggie", name: "Maggie",
                           look: Look(hat: .bow, pattern: .sleepsuit)),
                CastMember(id: "burns", name: "Mr Burns",
                           look: Look(pattern: .greenSuit)),
                CastMember(id: "flanders", name: "Ned Flanders",
                           look: Look(hat: .messyHair, accessories: [.mustache, .nerdGlasses], pattern: .jumper, hair: "o")),
                CastMember(id: "milhouse", name: "Milhouse",
                           look: Look(hat: .messyHair, accessories: [.nerdGlasses], pattern: .redShirt, hair: "U")),
                CastMember(id: "krusty", name: "Krusty",
                           look: Look(hat: .curlyHair, pattern: .shirt, hair: "N")),
            ]
        case "starWars":
            return [
                CastMember(id: "luke", name: "Luke",
                           look: Look(hat: .messyHair, pattern: .robe, held: .greenBlade, hair: "y")),
                CastMember(id: "leia", name: "Leia",
                           look: Look(hat: .buns, pattern: .whiteRobe, hair: "k")),
                CastMember(id: "han", name: "Han",
                           look: Look(hat: .messyHair, pattern: .vest, hair: "k")),
                CastMember(id: "chewbacca", name: "Chewbacca",
                           look: Look(hat: .messyHair, accessories: [.bushyBeard], pattern: .fur, hair: "o", beard: "o")),
                CastMember(id: "vader", name: "Darth Vader",
                           look: Look(hat: .darkHelmet, pattern: .darkRobe, cape: "K", held: .redBlade)),
                CastMember(id: "obiwan", name: "Obi-Wan",
                           look: Look(hat: .robeHood, accessories: [.bushyBeard], pattern: .robe, cape: "o", held: .blueBlade, beard: "O")),
                CastMember(id: "rey", name: "Rey",
                           look: Look(hat: .buns, pattern: .robe, held: .blueBlade, hair: "k")),
                CastMember(id: "kylo", name: "Kylo Ren",
                           look: Look(hat: .longHair, pattern: .darkRobe, cape: "K", held: .redBlade, hair: "j")),
                CastMember(id: "mandalorian", name: "The Mandalorian",
                           look: Look(hat: .hunterHelmet, pattern: .greyArmour, cape: "o")),
            ]
        case "northPole":
            // Santa Claude and the household at the North Pole: his workshop's elves, two of
            // the reindeer that pull the sleigh, and the toys and treats that come to life.
            return [
                CastMember(id: "santa", name: "Santa Claude",
                           look: Look(hat: .santa, accessories: [.longBeard], pattern: .santaSuit, held: .giftSack)),
                CastMember(id: "mrsClaude", name: "Mrs Claude",
                           look: Look(hat: .buns, accessories: [.roundGlasses, .pearls], pattern: .santaDress,
                                      held: .candyCane, hair: "W")),
                CastMember(id: "headElf", name: "The Head Elf",
                           look: Look(hat: .elfHat, accessories: [.stripedScarf], pattern: .elfTunic, held: .niceList)),
                CastMember(id: "toymaker", name: "The Toymaker",
                           look: Look(hat: .elfHat, accessories: [.nerdGlasses], pattern: .elfTunic, held: .present)),
                CastMember(id: "dasher", name: "Dasher",
                           look: Look(hat: .antlers, accessories: [.goldChain], pattern: .fur)),
                CastMember(id: "blitzen", name: "Blitzen",
                           look: Look(hat: .antlers, accessories: [.scarf], pattern: .fur)),
                CastMember(id: "snowman", name: "The Snowman",
                           look: Look(hat: .topHat, accessories: [.scarf], pattern: .snowSuit)),
                CastMember(id: "gingerbread", name: "Gingerbread",
                           look: Look(accessories: [.bowTie], pattern: .gingerbread)),
                CastMember(id: "nutcracker", name: "The Nutcracker",
                           look: Look(hat: .bearskin, accessories: [.mustache], pattern: .soldierCoat)),
            ]
        default:
            return []
        }
    }

    /// Who fills in once every main character is taken, and who subagents play.
    static func extras(_ key: String) -> [CastMember] {
        typealias Look = PixelArt.Look
        switch key {
        case "middleEarth":
            return [
                CastMember(id: "hobbit", name: "A hobbit", look: Look(hat: .curlyHair, pattern: .waistcoat)),
                CastMember(id: "elf", name: "An elf", look: Look(hat: .circlet, pattern: .tunic, cape: "g", held: .longbow)),
                CastMember(id: "ranger", name: "A ranger", look: Look(hat: .hood, pattern: .tunic, cape: "g", held: .sword)),
            ]
        case "harryPotter":
            return [
                CastMember(id: "pupil", name: "A pupil",
                           look: Look(hat: .schoolHat, pattern: .schoolRobe, held: .wand)),
                CastMember(id: "pupilScarf", name: "A pupil",
                           look: Look(hat: .ponytail, accessories: [.stripedScarf], pattern: .schoolRobe, held: .wand)),
            ]
        case "starWars":
            return [
                CastMember(id: "trooper", name: "A stormtrooper", look: Look(hat: .trooperHelmet, pattern: .whiteArmour)),
                CastMember(id: "pilot", name: "A pilot", look: Look(hat: .pilotHelmet, pattern: .plain)),
                CastMember(id: "jedi", name: "A Jedi", look: Look(hat: .robeHood, pattern: .robe, held: .greenBlade)),
            ]
        case "simpsons":
            return [
                CastMember(id: "townsperson", name: "A townsperson", look: Look(hat: .cap, pattern: .shirt)),
                CastMember(id: "worker", name: "A plant worker", look: Look(hat: .messyHair, accessories: [.necktie], pattern: .shirt)),
            ]
        case "northPole":
            return [
                CastMember(id: "elf", name: "An elf", look: Look(hat: .elfHat, pattern: .elfTunic, held: .present)),
                CastMember(id: "elfCane", name: "An elf", look: Look(hat: .elfHat, pattern: .elfTunic, held: .candyCane)),
                CastMember(id: "reindeer", name: "A reindeer", look: Look(hat: .antlers, pattern: .fur)),
            ]
        default:
            return []
        }
    }

    // MARK: Favourites

    /// The characters a user has starred for a cast, in the order starred. They are cast
    /// first; everyone else from the same film or show still appears after them. Choices saved
    /// by the version that switched characters on and off are read as favourites.
    static func favourites(_ key: String) -> [String] {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: "favourites." + key) { return saved }
        if let chosen = defaults.stringArray(forKey: "characters." + key), chosen.count < main(key).count {
            return chosen
        }
        return []
    }

    static func setFavourite(_ id: String, in key: String, to on: Bool) {
        var list = favourites(key).filter { $0 != id }
        if on { list.append(id) }
        UserDefaults.standard.set(list, forKey: "favourites." + key)
        UserDefaults.standard.removeObject(forKey: "characters." + key)
        Casting.shared.recast(key)
    }

    static func clearFavourites(in key: String) {
        UserDefaults.standard.set([String](), forKey: "favourites." + key)
        UserDefaults.standard.removeObject(forKey: "characters." + key)
        Casting.shared.recast(key)
    }
}

/// Decides which character each agent plays, so that every main character is played by at
/// most one agent at a time. Favourites are cast first, in the order starred; then the rest of
/// the film or show's characters, each agent with its own stable order of preference. Only
/// once every character is taken do agents play extras. An agent keeps its part while it is
/// on the floor.
final class Casting {
    static let shared = Casting()

    /// For each cast, which character each agent is playing.
    private var parts: [String: [String: String]] = [:]

    func member(for agentID: String, theme: Theme) -> CastMember? {
        guard let key = Cast.key(for: theme) else { return nil }
        let main = Cast.main(key)
        let extras = Cast.extras(key)
        var random = StableRandom(seed: agentID + "/" + key)
        // Subagents are too small to make out a costume, and should not take a main part.
        if agentID.contains("/") { return extras[random.next(extras.count)] }
        if let id = parts[key]?[agentID], let member = (main + extras).first(where: { $0.id == id }) {
            return member
        }
        let taken = Set(parts[key, default: [:]].values)
        let favourites = Cast.favourites(key)
        var order = favourites.compactMap { id in main.first { $0.id == id } }
        var rest = main.filter { !favourites.contains($0.id) }
        for index in stride(from: rest.count - 1, to: 0, by: -1) {
            rest.swapAt(index, random.next(index + 1))
        }
        order += rest
        let member = order.first { !taken.contains($0.id) } ?? extras[random.next(extras.count)]
        parts[key, default: [:]][agentID] = member.id
        return member
    }

    /// Frees the parts of agents that have left.
    func release(keeping agentIDs: Set<String>) {
        for key in parts.keys {
            parts[key] = parts[key]?.filter { agentIDs.contains($0.key) }
        }
    }

    /// Starts the casting over, after the favourites change.
    func recast(_ key: String) {
        parts[key] = [:]
    }
}
