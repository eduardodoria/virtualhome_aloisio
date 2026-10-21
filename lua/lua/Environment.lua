-- Casa Aloisio: real sun and moon for the chosen date and time, sky, light, fog and the time panel.
--
-- World axes: X = east, Y = up, Z = south. The sky cubemaps (lua/skytable.lua) are baked with the
-- sun at azimuth 0 (north, -Z); the Sky rotation turns them to the real azimuth.

local SkyTable = require("skytable")

local Environment = {
    properties = {
        { name = "year", displayName = "Year", type = "int", default = 2026 },
        { name = "month", displayName = "Month", type = "int", default = 10 },
        { name = "day", displayName = "Day", type = "int", default = 18 },
        { name = "hour", displayName = "Hour (local)", type = "float", default = 16.5 },
        { name = "utcOffset", displayName = "UTC offset", type = "float", default = -3.0 },
        { name = "latitude", displayName = "Latitude", type = "float", default = -11.0469473 },
        { name = "longitude", displayName = "Longitude", type = "float", default = -37.1447409 },
        { name = "timeScale", displayName = "Time scale (s per s)", type = "float", default = 0.0 },
        { name = "showPanel", displayName = "Show panel", type = "bool", default = true },
    }
}

local SPEEDS = { 0, 60, 300, 1200 }                 -- seconds of scene time per real second
local LIGHT_MODES = { "auto", "on", "off" }

-- ------------------------------------------------------------------ date helpers
local function julianDayNumber(y, m, d)
    local a = math.floor((14 - m) / 12)
    local yy = y + 4800 - a
    local mm = m + 12 * a - 3
    return d + math.floor((153 * mm + 2) / 5) + 365 * yy + math.floor(yy / 4) - math.floor(yy / 100) + math.floor(yy / 400) - 32045
end

local function fromJulianDayNumber(j)
    local a = j + 32044
    local b = math.floor((4 * a + 3) / 146097)
    local c = a - math.floor(146097 * b / 4)
    local d = math.floor((4 * c + 3) / 1461)
    local e = c - math.floor(1461 * d / 4)
    local m = math.floor((5 * e + 2) / 153)
    local day = e - math.floor((153 * m + 2) / 5) + 1
    local month = m + 3 - 12 * math.floor(m / 10)
    local year = 100 * b + d - 4800 + math.floor(m / 10)
    return year, month, day
end

local function daysInMonth(y, m)
    if m == 12 then return 31 end
    return julianDayNumber(y, m + 1, 1) - julianDayNumber(y, m, 1)
end

-- ------------------------------------------------------------------ astronomy (low precision, Astronomical Almanac)
local rad, deg, sin, cos = math.rad, math.deg, math.sin, math.cos

local function equatorialToHorizontal(ra, dec, lstDeg, lat)
    local ha = rad(lstDeg) - ra
    local phi = rad(lat)
    local el = math.asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(ha))
    local az = math.atan(-sin(ha), math.tan(dec) * cos(phi) - sin(phi) * cos(ha))
    az = deg(az) % 360
    local e = deg(el)
    -- atmospheric refraction (Bennett), lifts the sun about half a degree at the horizon
    if e > -2 then
        e = e + 1.02 / math.tan(rad(e + 10.3 / (e + 5.11))) / 60
    end
    return e, az
end

local function celestial(self)
    local jd = julianDayNumber(self.year, self.month, self.day) - 0.5 + (self.hour - self.utcOffset) / 24
    local n = jd - 2451545.0
    local eps = rad(23.439 - 0.0000004 * n)
    local gmst = (280.46061837 + 360.98564736629 * n) % 360
    local lst = gmst + self.longitude

    -- sun
    local L = (280.460 + 0.9856474 * n) % 360
    local g = rad((357.528 + 0.9856003 * n) % 360)
    local lambdaS = rad(L + 1.915 * sin(g) + 0.020 * sin(2 * g))
    local ra = math.atan(cos(eps) * sin(lambdaS), cos(lambdaS))
    local dec = math.asin(sin(eps) * sin(lambdaS))
    local sunEl, sunAz = equatorialToHorizontal(ra, dec, lst, self.latitude)

    -- moon (main periodic terms, about 0.5 deg)
    local Lm = 218.316 + 13.176396 * n
    local Mm = rad(134.963 + 13.064993 * n)
    local F = rad(93.272 + 13.229350 * n)
    local D = rad(297.850 + 12.190749 * n)
    local lambdaM = rad(Lm + 6.289 * sin(Mm) + 1.274 * sin(2 * D - Mm) + 0.658 * sin(2 * D))
    local betaM = rad(5.128 * sin(F))
    local raM = math.atan(sin(lambdaM) * cos(eps) - math.tan(betaM) * sin(eps), cos(lambdaM))
    local decM = math.asin(sin(betaM) * cos(eps) + cos(betaM) * sin(eps) * sin(lambdaM))
    local moonEl, moonAz = equatorialToHorizontal(raM, decM, lst, self.latitude)
    local elongation = math.acos(cos(lambdaM - lambdaS) * cos(betaM))
    local phase = (1 - cos(elongation)) / 2

    return sunEl, sunAz, moonEl, moonAz, phase, rad(lst)
end

local function directionFromHorizontal(el, az)
    local e, a = rad(el), rad(az)
    return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))
end

local function smoothstep(a, b, x)
    local t = math.max(0, math.min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
end

local function lerp(a, b, t) return a + (b - a) * t end

local function tableAt(el)
    local first, last = SkyTable[1], SkyTable[#SkyTable]
    if el <= first.elevation then return first, first, 0 end
    if el >= last.elevation then return last, last, 0 end
    for i = 1, #SkyTable - 1 do
        local a, b = SkyTable[i], SkyTable[i + 1]
        if el >= a.elevation and el <= b.elevation then
            return a, b, (el - a.elevation) / (b.elevation - a.elevation)
        end
    end
    return last, last, 0
end

local function lerp3(a, b, t)
    return { lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t) }
end

-- ------------------------------------------------------------------ lifecycle
function Environment:init()
    self.sunEntity = self.scene:findEntity("Sun")
    self.skyEntity = self.scene:findEntity("Sky")
    self.fogEntity = self.scene:findEntity("Fog")
    self.sun = self.sunEntity ~= NULL_ENTITY and Light(self.scene, self.sunEntity) or nil
    self.sky = self.skyEntity ~= NULL_ENTITY and SkyBox(self.scene, self.skyEntity) or nil
    self.fog = self.fogEntity ~= NULL_ENTITY and Fog(self.scene, self.fogEntity) or nil
    self.skyFile = nil
    self.speedIndex = 1
    for i, s in ipairs(SPEEDS) do
        if math.abs(s - self.timeScale) < 0.001 then self.speedIndex = i end
    end
    self.lightMode = "auto"
    self.lightsOn = false
    self.dirty = true
    self.panelVisible = self.showPanel
    self.revision = 0              -- bumped on every change, the HUD panel refreshes from it
    self:collectLamps()
    -- room reflection probes (Probe_Sala, Probe_WC): captured again when the light changes
    self.probes = {}
    for _, name in ipairs({ "Probe_Sala", "Probe_WC" }) do
        local e = self.scene:findEntity(name)
        if e ~= NULL_ENTITY then table.insert(self.probes, ReflectionProbe(self.scene, e)) end
    end
    self.probeSunEl, self.probeLights, self.probeWait = nil, nil, 0
    CasaEnvironment = self         -- the HUD scene's Panel script talks to us through this
    RegisterEngineEvent(self, "onUpdate")
    RegisterEngineEvent(self, "onKeyDown")
end

-- house lamps: point lights named Luz_1..Luz_N, glowing shades named Lampada_1..Lampada_N
function Environment:collectLamps()
    self.lamps = {}
    for i = 1, 64 do
        local e = self.scene:findEntity("Luz_" .. i)
        if e == NULL_ENTITY then break end
        local light = Light(self.scene, e)
        table.insert(self.lamps, { entity = e, light = light, intensity = light.intensity, object = Object(self.scene, e) })
    end
    self.shades = {}
    for i = 1, 64 do
        local e = self.scene:findEntity("Lampada_" .. i)
        if e == NULL_ENTITY then break end
        table.insert(self.shades, Object(self.scene, e))
    end
end

-- ------------------------------------------------------------------ time
function Environment:addDays(n)
    local j = julianDayNumber(self.year, self.month, self.day) + n
    self.year, self.month, self.day = fromJulianDayNumber(j)
    self.dirty = true
end

function Environment:addMonths(n)
    local m = self.month - 1 + n
    self.year = self.year + math.floor(m / 12)
    self.month = m % 12 + 1
    self.day = math.min(self.day, daysInMonth(self.year, self.month))
    self.dirty = true
end

function Environment:addHours(h)
    self.hour = self.hour + h
    while self.hour >= 24 do self.hour = self.hour - 24; self:addDays(1) end
    while self.hour < 0 do self.hour = self.hour + 24; self:addDays(-1) end
    self.dirty = true
end

function Environment:setNow()
    if os and os.date then
        local t = os.date("*t")
        self.year, self.month, self.day = t.year, t.month, t.day
        self.hour = t.hour + t.min / 60 + t.sec / 3600
        self.dirty = true
    end
end

function Environment:onUpdate()
    local scale = SPEEDS[self.speedIndex]
    if scale ~= 0 then
        self:addHours(Engine.deltatime * scale / 3600)
    end
    if self.dirty then
        self.dirty = false
        self:apply()
        self.revision = self.revision + 1
    end
    self:updateLamps()
    self:updateProbes()
end

-- the probes hold a snapshot of the rooms: take a new one once the sun has moved a couple of degrees or
-- the lamps went on or off, at most once a second (each capture renders the rooms six times)
function Environment:updateProbes()
    if #self.probes == 0 or not self.sunEl then return end
    self.probeWait = self.probeWait - Engine.deltatime
    local stale = self.probeSunEl == nil or math.abs(self.sunEl - self.probeSunEl) > 2.0 or self.probeLights ~= self.lightsOn
    if stale and self.probeWait <= 0 then
        for _, probe in ipairs(self.probes) do probe:refresh() end
        self.probeSunEl, self.probeLights, self.probeWait = self.sunEl, self.lightsOn, 1.0
    end
end

-- ------------------------------------------------------------------ sky, sun, moon, fog
function Environment:apply()
    local sunEl, sunAz, moonEl, moonAz, phase, lst = celestial(self)
    self.sunEl, self.sunAz, self.moonEl, self.moonAz, self.moonPhase = sunEl, sunAz, moonEl, moonAz, phase

    local a, b, t = tableAt(sunEl)
    local sunTab = lerp3(a.sun, b.sun, t)
    local horizon = lerp3(a.horizon, b.horizon, t)
    local exposure = lerp(a.exposure, b.exposure, t)
    local night = smoothstep(-4, -12, sunEl)

    -- sky: cubemap of the nearest baked elevation, turned to the sun azimuth
    local nearest = (t < 0.5) and a or b
    if self.sky then
        if nearest.file ~= self.skyFile then
            self.sky:setTexture(nearest.file)
            self.skyFile = nearest.file
        end
        self.sky.rotation = -sunAz
        local rot = rad(-sunAz)
        local e = rad(sunEl)
        self.sky:setShaderUniform("sunDir", Vector4(0, sin(e), -cos(e), smoothstep(-1.5, 0.5, sunEl)))
        local m = math.max(sunTab[1], sunTab[2], sunTab[3], 1e-4)
        self.sky:setShaderUniform("sunColor", Vector4(math.min(1, sunTab[1] / m + 0.25), math.min(1, sunTab[2] / m + 0.25),
                                                      math.min(1, sunTab[3] / m + 0.25), rot))
        -- the moon in the sky's local frame: undo the sky rotation
        local mw = directionFromHorizontal(moonEl, moonAz)
        local c, s = cos(-rot), sin(-rot)
        local ml = Vector3(c * mw.x + s * mw.z, mw.y, -s * mw.x + c * mw.z)
        self.sky:setShaderUniform("moonDir", Vector4(ml.x, ml.y, ml.z, phase))
        local moonUp = smoothstep(-2, 8, moonEl)
        self.sky:setShaderUniform("nightSky", Vector4(night, moonUp * phase * night, 0.8 * night, lst))
        -- IBL exposure: the eye opens up at night so the moonlit yard stays readable
        local ibl = 1.0 + 0.4 * smoothstep(2, -6, sunEl) + 0.5 * night
        -- by day a camera's white balance takes the blue out of the skylight in shade and indoors
        -- (the sun is left as it is); at night the moonlight keeps its blue
        local wb = smoothstep(-2, 6, sunEl)
        self.sky.color = Vector4(ibl * (1 + 0.05 * wb), ibl, ibl * (1 - 0.16 * wb), 1.0)
    end

    -- one directional light: the sun by day, the moon at night
    if self.sun then
        local lum = 0.2126 * sunTab[1] + 0.7152 * sunTab[2] + 0.0722 * sunTab[3]
        local sunI = 0.19 * lum * exposure
        -- a full moon at ~3.5% of the noon sun: dark enough to read as night, light enough to walk
        local moonI = 0.12 * (0.15 + 0.85 * phase) * smoothstep(-2, 10, moonEl) * night
        if sunI >= moonI then
            local d = directionFromHorizontal(math.max(sunEl, 0.5), sunAz)
            local m = math.max(sunTab[1], sunTab[2], sunTab[3], 1e-4)
            self.sun.direction = Vector3(-d.x, -d.y, -d.z)
            -- the single-scattering table is warmer than the eye sees the sun (about 2900 K at 12 deg,
            -- 3800 K in measurements): compress the ratios, sunsets stay orange
            self.sun.color = Vector3((sunTab[1] / m) ^ 0.7, (sunTab[2] / m) ^ 0.7, (sunTab[3] / m) ^ 0.7)
            self.sun.intensity = sunI
        else
            local d = directionFromHorizontal(math.max(moonEl, 1.0), moonAz)
            self.sun.direction = Vector3(-d.x, -d.y, -d.z)
            self.sun.color = Vector3(0.62, 0.72, 1.0)
            self.sun.intensity = moonI
        end
    end

    -- fog takes the horizon colour so the far land melts into the sky
    if self.fog then
        local f = 1.0 + 1.2 * night
        self.fog.color = Vector3(math.min(1, horizon[1] * f + 0.01 * night), math.min(1, horizon[2] * f + 0.013 * night),
                                 math.min(1, horizon[3] * f + 0.02 * night))
    end

    local want = (self.lightMode == "on") or (self.lightMode == "auto" and sunEl < -1.0)
    if want ~= self.lightsOn then
        self.lightsOn = want
        for _, shade in ipairs(self.shades) do shade.visible = want end
    end
end

-- house lamps: all of them on or off; the engine gives its light slots (6, the sun or moon included)
-- to the lit lamps nearest the viewer
function Environment:updateLamps()
    if #self.lamps == 0 or self.lampsShown == self.lightsOn then return end
    self.lampsShown = self.lightsOn
    for _, l in ipairs(self.lamps) do
        l.light.intensity = self.lightsOn and l.intensity or 0
    end
end


function Environment:cycleSpeed()
    self.speedIndex = self.speedIndex % #SPEEDS + 1
    self.revision = self.revision + 1
end

function Environment:cycleLights()
    for i, m in ipairs(LIGHT_MODES) do
        if m == self.lightMode then self.lightMode = LIGHT_MODES[i % #LIGHT_MODES + 1]; break end
    end
    self.dirty = true
end

function Environment:setHour(h)
    self.hour = math.max(0, math.min(23.999, h))
    self.dirty = true
end

function Environment:onKeyDown(key, repeated, mods)
    if key == Input.KEY_RIGHT_BRACKET then self:addHours(0.25)
    elseif key == Input.KEY_LEFT_BRACKET then self:addHours(-0.25)
    elseif key == Input.KEY_PERIOD then self:addDays(1)
    elseif key == Input.KEY_COMMA then self:addDays(-1)
    elseif key == Input.KEY_L and not repeated then self:cycleLights()
    elseif key == Input.KEY_T and not repeated then self:cycleSpeed()
    end
end

return Environment
