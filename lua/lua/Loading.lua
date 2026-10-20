-- Casa Aloisio: loading screen (Project Settings -> Loading). It covers the start of the main scene
-- while its models, textures and sky stream in, then waits a moment more for the vegetation, whose
-- chunks are built over a few frames once the terrain is up, and fades out. It looks like the web
-- page's own loading screen (web/shell.html), which hands over to it. The widgets are laid out in the
-- editor (scenes/loading.scene, made by source/tools/build_ui_scenes.py); this script animates them.

local Loading = {
    properties = {
        { name = "settle", displayName = "Seconds held after loading (vegetation)", type = "float", default = 1.2 },
        { name = "settleFrames", displayName = "Frames held after loading, at least", type = "int", default = 30 },
        { name = "fade", displayName = "Fade out seconds", type = "float", default = 0.5 },
    }
}

local BAR_W = 340

local function wrap(scene, kind, name)
    local e = scene:findEntity(name)
    if e == NULL_ENTITY then return nil end
    return kind(scene, e)
end

function Loading:init()
    self.back = wrap(self.scene, Image, "Fundo")
    self.title = wrap(self.scene, Text, "Titulo")
    self.track = wrap(self.scene, Image, "Trilha")
    self.bar = wrap(self.scene, Image, "Barra")
    self.status = wrap(self.scene, Text, "Estado")
    self.parts = { self.back, self.title, self.track, self.bar, self.status }
    self.shown = 0
    if self.status then self.status.text = "Preparando a cena…" end
    RegisterEngineEvent(self, "onUpdate")
    RegisterEngineEvent(self, "onSceneLoaded")
end

function Loading:setAlpha(a)
    for _, p in ipairs(self.parts) do
        if p then p.alpha = a end
    end
end

function Loading:onSceneLoaded()
    -- only while this loading scene is on screen
    if Engine.isSceneRunning(self.scene) and SceneManager.holdLoading() then
        self.holding = 0
        self.holdFrames = 0
    end
end

function Loading:onUpdate()
    local dt = Engine.deltatime
    if self.holding then
        -- the vegetation is built a few pieces per frame, so a slow device needs frames, not seconds
        self.holdFrames = self.holdFrames + 1
        if self.holdFrames < self.settleFrames then
            self.holding = math.min(self.holding + dt, self.settle * 0.9)
        else
            self.holding = self.holding + dt
        end
        self.shown = self.shown + (1 - self.shown) * math.min(1, dt * 8)
        if self.status then self.status.text = "Plantando a vegetação…" end
        local fadeAt = self.settle
        if self.holding >= fadeAt then
            self:setAlpha(math.max(0, 1 - (self.holding - fadeAt) / self.fade))
        end
        if self.holding >= fadeAt + self.fade then
            self.holding = nil
            SceneManager.releaseLoading()
            self:setAlpha(1)
            self.shown = 0
        end
    elseif SceneManager.loading then
        -- ease the bar toward the progress, which moves in steps
        self.shown = self.shown + (SceneManager.loadingProgress * 0.9 - self.shown) * math.min(1, dt * 6)
    end
    if self.bar then self.bar:setSize(math.max(1, BAR_W * self.shown), 6) end
end

return Loading
