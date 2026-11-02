-- Native cards already support per-card surfaces, including flip/tear effects.
-- Keep this mapping in sync with the artist's 10-column, 24x32 atlas.
local art = {
    {"Co-op High Cantle Saddle", 7},
    {"Co-op Deflect Armor", 20},
    {"Co-op Abbey of Kings", 21},
    {"Co-op In-Law", 0},
    {"Co-op Knight Spirit", 1},
    {"Co-op Rally Order", 2},
    {"Co-op Mechanism Order", 3},
    {"Co-op Sweeping Blade", 4},
    {"Co-op Gun Knight Duet", 5},
    {"Co-op Timar Cavalry Pact", 6},
    {"Co-op Warrant", 10},
    {"Co-op Bounty Cavalry", 11},
    {"Co-op Joust Compact", 12},
    {"Co-op Excommunication", 13},
    {"Co-op Divisive Edict", 14},
    {"Co-op Revenant Bell", 15},
    {"Co-op Royal Vigil", 16},
    {"Co-op Blade Revenge", 17},
    {"Co-op Grand Phalanx", 18},
    {"Co-op Cheval de Frise", 19},
}
if isfile("assets/gfx/coop_cards_runtime.png") then
    newsrf("coop_cards", "assets/gfx/coop_cards_runtime.png")
    -- tear_apart() samples x=240..261 on the card's own surface.
    -- Copy its original mask, without changing any native surface or callback.
    local previous = spritesheet()
    local mask = {}
    spritesheet("cards")
    for y=0,28 do for x=0,21 do
        mask[#mask+1] = sget(240+x,y)
    end end
    spritesheet("coop_cards")
    local i=1
    for y=0,28 do for x=0,21 do
        sset(240+x,y,mask[i]);i=i+1
    end end
    spritesheet(previous)
    for _, entry in ipairs(art) do
        for _, card in ipairs(CARDS) do
            if card.id == entry[1] then
                card.gid = entry[2]
                card.spsheet = "coop_cards"
                break
            end
        end
    end
    if _log then _log("[COOP ART] 17 card faces loaded with native tear mask") end
end
