-- Casa Aloisio: time panel and performance panel. Live in the HUD (UI) scene, a child scene of the main
-- scene, and drive the Environment script of the main scene through the CasaEnvironment global.
-- The widgets are laid out in the editor (scenes/hud.scene, made by source/tools/build_ui_scenes.py);
-- this script finds them by name and gives them their behaviour.
-- A clock button in the bottom-left corner (or the H key) opens and closes the time panel; the gauge
-- button beside it (or F3) shows the frame rate and the quality options in the top-left corner.

local Panel = {
    properties = {
        { name = "startVisible", displayName = "Start visible", type = "bool", default = false },
        { name = "showStats", displayName = "Show the frame rate at start", type = "bool", default = false },
    }
}

local MONTHS = { "jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez" }
local SPEED_LABELS = { "Tempo parado", "1 min/s", "5 min/s", "20 min/s" }
local LIGHT_LABELS = { auto = "Luzes: auto", on = "Luzes: ligadas", off = "Luzes: desligadas" }
-- help line while a game controller is connected (the controls are in lua/Walker.lua)
local HELP_PAD = "Controle: analógico esquerdo anda, direito olha · RT corre · Y voa (A sobe, B desce) · LB RB vistas · " ..
    "direcional hora e dia · X luzes · Start painel · Back som"

-- debug quality options (gauge button / F3): each button cycles through its levels
local RES_LEVELS = { 1.0, 0.75, 0.5 }
local SHADOW_LEVELS = { "altas", "baixas", "desligadas" }
local VEG_LEVELS = { 1.0, 0.7, 0.45 }

function Panel:init()
    self.widgets = {}              -- keeps every wrapper alive
    self.visible = self.startVisible
    self.seen = -1
    self:bindTimePanel()
    self:bindStats()
    self.help = self:widget(Text, "Ajuda")
    self.padHelp = false
    CasaPanel = self               -- the visitor's controller opens and closes the time panel
    RegisterEngineEvent(self, "onUpdate")
    RegisterEngineEvent(self, "onKeyDown")
end

local function env() return CasaEnvironment end

-- the scene entity of that name wrapped as kind
function Panel:widget(kind, name)
    local e = self.scene:findEntity(name)
    if e == NULL_ENTITY then
        print("Panel: missing widget " .. name)
        return nil
    end
    local w = kind(self.scene, e)
    table.insert(self.widgets, w)
    return w
end

-- a button of the scene that runs action(environment) when released
function Panel:envButton(name, action)
    local b = self:widget(Button, name)
    if b then
        b:getButtonComponent().onRelease = function()
            local e = env()
            if e then action(e) end
        end
    end
    return b
end

function Panel:bindTimePanel()
    self.panel = self:widget(Image, "PainelHorario")
    self.dateText = self:widget(Text, "Data")
    self.timeText = self:widget(Text, "Hora")
    self.sunText = self:widget(Text, "InfoSol")
    self.lightButton = self:envButton("BotaoLuzes", function(e) e:cycleLights() end)
    self:envButton("MenosDia", function(e) e:addDays(-1) end)
    self:envButton("MaisDia", function(e) e:addDays(1) end)
    self:envButton("MenosMes", function(e) e:addMonths(-1) end)
    self:envButton("MaisMes", function(e) e:addMonths(1) end)
    self:envButton("MenosHora", function(e) e:addHours(-1) end)
    self:envButton("MaisHora", function(e) e:addHours(1) end)
    self:envButton("Menos10", function(e) e:addHours(-1 / 6) end)
    self:envButton("Mais10", function(e) e:addHours(1 / 6) end)
    self.speedButton = self:envButton("BotaoTempo", function(e) e:cycleSpeed() end)
    self:envButton("BotaoAgora", function(e) e:setNow() end)

    local panelScript = self
    self.slider = self:widget(Scrollbar, "BarraHora")
    if self.slider then
        self.slider:getScrollbarComponent().onChange = function(step)
            local e = env()
            if panelScript.updatingSlider or not e then return end
            e:setHour(step * 24)
        end
    end

    local toggle = self:widget(Button, "Relogio")
    if toggle then
        toggle:getButtonComponent().onRelease = function() panelScript:setVisible(not panelScript.visible) end
    end
    if self.panel then self.panel.visible = self.visible end
end

-- frame rate readout (average and worst frame of each half second) and the quality options
function Panel:bindStats()
    local panelScript = self
    local gauge = self:widget(Button, "Desempenho")
    if gauge then
        gauge:getButtonComponent().onRelease = function() panelScript:setStatsVisible(not panelScript.statsVisible) end
    end
    self.statsBack = self:widget(Image, "FpsFundo")
    self.statsText = self:widget(Text, "Fps")
    self.statsTime, self.statsFrames, self.statsWorst = 0, 0, 0

    self.resLevel, self.shadowLevel, self.vegLevel = 1, 1, 1
    local function option(name, action)
        local o = self:widget(Button, name)
        if o then o:getButtonComponent().onRelease = action end
        return o
    end
    self.resButton = option("OpcaoResolucao", function() panelScript:cycleResolution() end)
    self.shadowButton = option("OpcaoSombras", function() panelScript:cycleShadows() end)
    self.vegButton = option("OpcaoVegetacao", function() panelScript:cycleVegetation() end)
    self.ssaoButton = option("OpcaoSSAO", function() panelScript:toggleEffect("ssaoEnabled") end)
    self.ssrButton = option("OpcaoSSR", function() panelScript:toggleEffect("ssrEnabled") end)
    self:labelOptions()
    self:setStatsVisible(self.showStats)
end

function Panel:labelOptions()
    if not (self.resButton and self.shadowButton and self.vegButton and self.ssaoButton and self.ssrButton) then return end
    self.resButton.label = string.format("Resolução: %d%%", RES_LEVELS[self.resLevel] * 100)
    self.shadowButton.label = "Sombras: " .. SHADOW_LEVELS[self.shadowLevel]
    self.vegButton.label = string.format("Vegetação: %d%%", VEG_LEVELS[self.vegLevel] * 100)
    local e = env()
    local function onOff(on) return on and "ligado" or "desligado" end
    self.ssaoButton.label = "SSAO: " .. onOff(e and e.scene.ssaoEnabled)
    self.ssrButton.label = "SSR: " .. onOff(e and e.scene.ssrEnabled)
end

-- the 3D scene renders into a smaller target scaled to the window; the HUD stays sharp
function Panel:applyResolution()
    local e = env()
    if not e then return end
    local scale = RES_LEVELS[self.resLevel]
    local view = Engine.viewRect
    if scale < 1 and view.width > 0 then
        e.scene:setFixedResolutionSize(math.floor(view.width * scale), math.floor(view.height * scale))
        e.scene.fixedResolutionEnabled = true
        self.appliedView = { view.width, view.height }
    else
        e.scene.fixedResolutionEnabled = false
        self.appliedView = nil
    end
end

function Panel:cycleResolution()
    self.resLevel = self.resLevel % #RES_LEVELS + 1
    self:applyResolution()
    self:labelOptions()
end

function Panel:cycleShadows()
    local e = env()
    if not e or not e.sun then return end
    self.shadowLevel = self.shadowLevel % #SHADOW_LEVELS + 1
    local level = SHADOW_LEVELS[self.shadowLevel]
    e.sun.shadows = level ~= "desligadas"
    if level == "altas" then
        e.sun.numCascades = 2
        e.sun.range = 100
    elseif level == "baixas" then
        e.sun.numCascades = 1
        e.sun.range = 60
    end
    self:labelOptions()
end

function Panel:cycleVegetation()
    local e = env()
    if not e then return end
    self.vegLevel = self.vegLevel % #VEG_LEVELS + 1
    local entity = e.scene:findEntity("Terrain")
    if entity ~= NULL_ENTITY then
        self.terrain = self.terrain or Terrain(e.scene, entity)
        self.terrain.foliageDistanceScale = VEG_LEVELS[self.vegLevel]
    end
    self:labelOptions()
end

-- screen-space ambient occlusion and reflections, off in the scene: the meshes switch shader variants,
-- so every combination's variants are listed in the scene's shader keys for the export
function Panel:toggleEffect(field)
    local e = env()
    if not e then return end
    e.scene[field] = not e.scene[field]
    self:labelOptions()
end

function Panel:setStatsVisible(visible)
    self.statsVisible = visible
    if self.statsBack then self.statsBack.visible = visible end
end

function Panel:updateStats()
    local dt = Engine.deltatime
    self.statsTime = self.statsTime + dt
    self.statsFrames = self.statsFrames + 1
    if dt > self.statsWorst then self.statsWorst = dt end
    -- a reduced resolution follows the window size
    if self.appliedView then
        local view = Engine.viewRect
        if view.width ~= self.appliedView[1] or view.height ~= self.appliedView[2] then self:applyResolution() end
    end
    if self.statsTime >= 0.5 then
        if self.statsVisible and self.statsText then
            local avg = self.statsTime / self.statsFrames
            self.statsText.text = string.format("%.0f FPS · %.1f ms · pior %.1f ms", 1 / avg, avg * 1000, self.statsWorst * 1000)
        end
        self.statsTime, self.statsFrames, self.statsWorst = 0, 0, 0
    end
end

function Panel:setVisible(visible)
    self.visible = visible
    if self.panel then self.panel.visible = visible end
end

function Panel:refresh(e)
    if not (self.dateText and self.timeText and self.sunText and self.slider and self.speedButton and self.lightButton) then return end
    local h = math.floor(e.hour)
    local m = math.floor((e.hour - h) * 60 + 0.5)
    if m == 60 then h = h + 1; m = 0 end
    self.dateText.text = string.format("%02d %s %d", e.day, MONTHS[e.month], e.year)
    self.timeText.text = string.format("%02d:%02d", h % 24, m)
    if e.sunEl then
        self.sunText.text = string.format("Sol %.1f° de altura, azimute %.0f°   Lua %.0f%% iluminada", e.sunEl, e.sunAz,
            (e.moonPhase or 0) * 100)
    end
    self.updatingSlider = true
    self.slider.step = e.hour / 24
    self.updatingSlider = false
    self.speedButton.label = SPEED_LABELS[e.speedIndex] or SPEED_LABELS[1]
    self.lightButton.label = LIGHT_LABELS[e.lightMode] or LIGHT_LABELS.auto
end

-- with a controller connected the help line lists its buttons; the keyboard (or touch) one comes back after
function Panel:updateHelp()
    local pad = Input.numGamepads() > 0
    if not self.help or pad == self.padHelp then return end
    self.padHelp = pad
    if pad then
        self.helpBefore = self.help.text
        self.help.text = HELP_PAD
    elseif self.helpBefore then
        self.help.text = self.helpBefore
    end
end

function Panel:onUpdate()
    self:updateStats()
    self:updateHelp()
    local e = env()
    if e and e.revision ~= self.seen then
        self.seen = e.revision
        self:refresh(e)
    end
end

function Panel:onKeyDown(key, repeated, mods)
    if key == Input.KEY_H and not repeated then
        self:setVisible(not self.visible)
    elseif key == Input.KEY_F3 and not repeated then
        self:setStatsVisible(not self.statsVisible)
    end
end

return Panel
