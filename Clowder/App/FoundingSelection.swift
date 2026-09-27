import Foundation

/// Which candidates have been chosen for each founding role.
struct FoundingSelection: Equatable {
    var leader: Cat.ID?
    var deputy: Cat.ID?
    var medicineCat: Cat.ID?
    var members: [Cat.ID] = []

    var count: Int {
        [leader, deputy, medicineCat].compactMap(\.self).count + members.count
    }

    var nextRole: ClanFounding.Role {
        if leader == nil { .leader }
        else if deputy == nil { .deputy }
        else if medicineCat == nil { .medicineCat }
        else { .member }
    }

    func role(of id: Cat.ID) -> ClanFounding.Role? {
        if leader == id { .leader }
        else if deputy == id { .deputy }
        else if medicineCat == id { .medicineCat }
        else if members.contains(id) { .member }
        else { nil }
    }

    mutating func assign(_ id: Cat.ID, to role: ClanFounding.Role) {
        switch role {
        case .leader: leader = id
        case .deputy: deputy = id
        case .medicineCat: medicineCat = id
        case .member: members.append(id)
        }
    }

    mutating func remove(_ id: Cat.ID) {
        if leader == id { leader = nil }
        if deputy == id { deputy = nil }
        if medicineCat == id { medicineCat = nil }
        members.removeAll { $0 == id }
    }
}
