-- Generated alpha mask for bell.png (50x24, two 25x24 frames).
-- SUGAR maps PNG RGB to palette indices; transparent pixels can retain RGB.
-- Explicitly clear only alpha-zero pixels, preserving all opaque bell details.
newsrf("onlinecoop_bell_button","bell.png")
spritesheet("onlinecoop_bell_button")
local clear_runs={{0,0,49},{1,0,49},{2,0,49},{3,0,49},{4,0,10},{4,14,49},{5,0,9},{5,15,49},{6,0,8},{6,16,35},{6,39,49},{7,0,8},{7,16,34},{7,40,49},{8,0,9},{8,15,33},{8,41,49},{9,0,9},{9,15,33},{9,41,49},{10,0,5},{10,19,30},{10,44,49},{11,0,4},{11,20,29},{11,45,49},{12,0,3},{12,21,28},{12,46,49},{13,0,2},{13,22,27},{13,47,49},{14,0,2},{14,22,27},{14,47,49},{15,0,2},{15,22,27},{15,47,49},{16,0,2},{16,22,27},{16,47,49},{17,0,2},{17,22,27},{17,47,49},{18,0,2},{18,22,27},{18,47,49},{19,0,2},{19,22,27},{19,47,49},{20,0,1},{20,23,26},{20,48,49},{21,0,0},{21,24,25},{21,49,49},{22,0,0},{22,24,25},{22,49,49},{23,0,49}}
for _,run in ipairs(clear_runs) do
    for x=run[2],run[3] do sset(x,run[1],0) end
end
spritesheet("gfx")
