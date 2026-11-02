-- Native gfx: the small dissolving Knight at (208,336), 16x16.
-- Per-instance skin only: keep type 1's movement, cooldown and lift logic.
function coop_draw_phantom_knight(e,x,y)
    spritesheet("gfx")
    -- This source is already dark; native black-piece palette swapping would
    -- invert it a second time. Reset after drawing so other pieces are intact.
    pal_rst()
    local py=y+(PDY or -2)
    -- Keep the silhouette stable on both board colours. Native readiness
    -- animation remains responsible for indicating when this Knight can act.
    sspr(208,336,16,16,x,py)
    pal_rst()
end
