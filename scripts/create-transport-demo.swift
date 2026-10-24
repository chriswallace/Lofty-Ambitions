import Foundation
var game=TowerState.demoTower()
game.name="Express & Local"
game.cash=10_000_000
game.earnedStars=5
for _ in 0..<46 {try game.addFloor()}
try game.extendElevators()
try game.addElevator(.wide,from:0,to:29)
try game.addElevator(.express,from:0,to:50)
try game.addElevator(.wide,from:30,to:50)
func buildRoom(_ kind:RoomKind,floor:Int,slot:Int) throws {
    let blocked = game.elevators.contains { lift in
        guard let column=lift.column else{return false}
        return floor>=lift.bottom && floor<=lift.topFloor && slot<column+lift.footprintWidth && slot+kind.width>column
    }
    if !blocked {try game.build(kind,floor:floor,slot:slot)}
}
for floor in 5...50 {
    if floor%15 == 0 {
        try buildRoom(.garden,floor:floor,slot:0)
        try buildRoom(.restaurant,floor:floor,slot:32)
    } else if floor%7 == 0 {
        try buildRoom(.hotel,floor:floor,slot:0)
        try buildRoom(.housekeeping,floor:floor,slot:16)
        try buildRoom(.hotel,floor:floor,slot:32)
    } else if floor%3 == 0 {
        for slot in [0,4,8,12,16,20,32,36,40,44,48,52,56,60] {try buildRoom(.apartment,floor:floor,slot:slot)}
    } else {
        for slot in [0,9,18,32,41,50] {try buildRoom(.office,floor:floor,slot:slot)}
    }
}
for i in game.rooms.indices where game.rooms[i].kind.capacity>0 {game.rooms[i].occupancy=0.8}
game.events=["Transport sandbox: express cars serve G, 15, 30 and 45. Upper locals carry people onward to floor 50.","Built for experimenting. Campaign progression is already unlocked and the treasury has extra funds."]
for floor in [2,15,30,45,49,50] {
    if let room=game.rooms.first(where:{$0.floor==floor && $0.kind.capacity>0}) {
        for _ in 0..<5 {try game.requestTrip(roomID:room.id,from:0,to:floor)}
    }
}
game.advance(minutes:240)
let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
try encoder.encode(game.validated()).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
print("Created transport sandbox:",game.rooms.count,"rooms,",game.elevators.count,"banks,",game.completedTrips,"completed trips")
