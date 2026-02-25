import Vapor

func bcryptCostFromEnv() -> Int? {
    guard let raw = Environment.get("BCRYPT_COST"), let cost = Int(raw) else {
        return nil
    }
    return cost
}

func hashPassword(_ password: String) throws -> String {
    if let cost = bcryptCostFromEnv() {
        return try Bcrypt.hash(password, cost: cost)
    }
    return try Bcrypt.hash(password)
}

