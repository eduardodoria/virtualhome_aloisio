-- Casa Aloisio: ambient sound. Day and night beds crossfade with the sun (CasaEnvironment), bird
-- calls (bem-te-vi, coro-coro) come now and then by day, and everything is quieter inside the house.
-- M mutes. Recordings: freesound.org, CC0 (source/scripts/build_sounds.py).

local Ambience = {
    properties = {
        { name = "volume", displayName = "Volume", type = "float", default = 1.0 },
    }
}

local DAY_VOLUME, NIGHT_VOLUME, BIRD_VOLUME = 0.28, 0.3, 0.22
local HOUSE_CENTRE_X, HOUSE_CENTRE_Y = 6.915, 6.329
local TH = math.rad(214.8)

local function smoothstep(a, b, x)
    local t = math.max(0, math.min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
end

function Ambience:loop(file)
    local s = Sound(self.scene)
    s:loadSound(file)
    s.looping = true
    s.volume = 0
    s:play()
    table.insert(self.sounds, s)
    return s
end

function Ambience:init()
    self.sounds = {}                -- keep the wrappers: a collected one destroys its entity
    self.day = self:loop("sounds/ambiente_dia.ogg")
    self.night = self:loop("sounds/ambiente_noite.ogg")
    self.birds = {}
    for i = 1, 4 do
        local s = Sound(self.scene)
        s:loadSound(string.format("sounds/aves_%d.ogg", i))
        table.insert(self.birds, s)
        table.insert(self.sounds, s)
    end
    self.muted = false
    self.inside = 0
    CasaAmbience = self             -- the visitor's footsteps follow its mute
    self.nextBird = 15 + math.random() * 20
    RegisterEngineEvent(self, "onUpdate")
    RegisterEngineEvent(self, "onKeyDown")
end

-- is the camera inside the house walls (house-local frame of the SketchUp model)?
function Ambience:cameraInside()
    local cam = self.scene.camera
    if not cam or cam == NULL_ENTITY then return false end
    local p = Object(self.scene, cam):getWorldPosition()
    local wx, wy = p.x, -p.z
    local lx = math.cos(-TH) * wx - math.sin(-TH) * wy + HOUSE_CENTRE_X
    local ly = math.sin(-TH) * wx + math.cos(-TH) * wy + HOUSE_CENTRE_Y
    return lx > 2.1 and lx < 11.73 and ly > 2.68 and ly < 7.98 and p.y > 34.5 and p.y < 39
end

function Ambience:onUpdate()
    local dt = Engine.deltatime
    local env = CasaEnvironment
    local sunEl = env and env.sunEl or 30
    local dayFactor = smoothstep(-6, 4, sunEl)
    self.inside = self.inside + ((self:cameraInside() and 1 or 0) - self.inside) * math.min(1, dt * 2)
    local master = (self.muted and 0 or self.volume) * (1 - 0.55 * self.inside)
    self.day.volume = DAY_VOLUME * dayFactor * master
    self.night.volume = NIGHT_VOLUME * (1 - dayFactor) * master

    -- a bird call now and then by day, a little to either side
    self.nextBird = self.nextBird - dt
    if self.nextBird <= 0 then
        self.nextBird = 30 + math.random() * 60
        if dayFactor > 0.5 and master > 0 then
            local s = self.birds[math.random(#self.birds)]
            s.volume = BIRD_VOLUME * (0.4 + 0.6 * math.random()) * master * dayFactor
            s.pan = (math.random() * 2 - 1) * 0.6
            s:play()
        end
    end
end

function Ambience:onKeyDown(key, repeated, mods)
    if key == Input.KEY_M and not repeated then
        self.muted = not self.muted
    end
end

return Ambience
