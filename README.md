# pokéroo

## wat?

pokéroo is a bot i made to play pokémon firered while i work on ROM hacks, to quickly see if things are working.

it's a horrific mess of lua scripts designed to integrate with the GBA emulator mGBA and Pokémon FireRed. it will drive a bot to navigate the map by randomly pursuing points of interest, then button mash whenever it's doing anything else (eg. in menus or in battle).

i'm in the process of cleaning it up, so try not to look at it too closely.

it's not meant to play it _well_. it's not an exercise in training the ultimate pokémon bot - i'll just be happy when it's at the point where it can eventually navigate through most/all (?) of the game itself...even if it takes ten hours to reach viridian city.

no guarantees that this will work at all. since i'm working on some ROM hacks at the same time, some of the memory address it's referencing may not correspond to the retail ROMs. don't do anything silly like run this against any saves you care about, for example.

## dependencies

Uses [this fork of luafinding](https://github.com/barneyboo/Luafinding) for bot pathfinding

## TODO

- [ ] total refactor
- [ ] better logging
- [ ] intent logging (eg. "Heading towards OAK'S LAB")
- [ ] send status updates via websockets
- [ ] redirect logging to consume outside of mGBA
- [ ] stop trying to walk on water
- [ ] disable button bashing during evolution
- [ ] on map load, add a random item ball at a random location
- [x] add objects to collision map (eg. trainers, signs, etc.)
