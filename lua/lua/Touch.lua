-- Casa Aloisio: on-screen controls for phones and tablets. Lives in the HUD scene beside lua/Panel.lua and
-- drives the Walker of the main scene through the CasaWalker global.
-- The widgets (Toque*) are laid out in the editor (scenes/hud.scene, made by source/tools/build_ui_scenes.py):
--   joystick at the bottom left: walk, faster the further it is pushed;
--   Correr and Voar at the bottom right (Subir and Descer beside them while flying);
--   Vista at the top right: the next viewpoint;
--   a drag anywhere else looks around.
-- They show only on touch devices (System.isTouchDevice(): phones and tablets; in the editor, Play with
-- touch simulation on).
-- The fingers are read every frame from Input.getTouches(): a UI button is released as soon as any finger
-- lifts, and a touch that starts on a UI image never reaches the touch events.

local Touch = {
    properties = {
        { name = "alwaysVisible", displayName = "Always visible (to test with the mouse)", type = "bool", default = false },
    }
}

local STICK_RANGE = 70          -- canvas units from the centre of the joystick for full speed
local DEAD_ZONE = 0.12
local LOOK_SPEED = 0.2          -- degrees per canvas unit dragged
local TINT = Vector4(0.08, 0.09, 0.10, 0.8)
local TINT_ON = Vector4(0.89, 0.65, 0.29, 0.92)
local HELP_TOUCH = "Joystick à esquerda anda · arraste a tela para olhar · Correr, Voar e Vista nos botões · " ..
    "relógio abre este painel"
-- the UI canvas of a phone held upright: 1280 units across a portrait screen make every control tiny
local PORTRAIT_CANVAS = { 720, 1280 }

function Touch:init()
    self.widgets = {}
    self.base = self:widget(Image, "ToqueBase")
    self.knob = self:widget(Image, "ToqueAlavanca")
    self.runButton = self:widget(Image, "ToqueCorrer")
    self.flyButton = self:widget(Image, "ToqueVoar")
    self.upButton = self:widget(Image, "ToqueSubir")
    self.downButton = self:widget(Image, "ToqueDescer")
    self.viewButton = self:widget(Image, "ToqueVista")
    self.viewText = self:widget(Text, "ToqueVistaTexto")
    self.help = self:widget(Text, "Ajuda")
    self.helpKeys = self.help and self.help.text
    -- the rest of the HUD: a finger that starts there is the UI's, never a look drag
    self.uiAreas = { self:widget(UILayout, "PainelHorario"), self:widget(UILayout, "FpsFundo"),
                     self:widget(UILayout, "Relogio"), self:widget(UILayout, "Desempenho") }
    self.canvas = { Engine.preferredCanvasWidth, Engine.preferredCanvasHeight }
    self.fingers = {}           -- touch pointer -> { role, x, y, ... }
    self.running = false
    self:setActive(self.alwaysVisible or System.isTouchDevice())
    if self.active then RegisterEngineEvent(self, "onUpdate") end
end

-- the scene entity of that name wrapped as kind (the wrappers are kept, or the GC destroys the entities)
function Touch:widget(kind, name)
    local e = self.scene:findEntity(name)
    if e == NULL_ENTITY then
        print("Touch: missing widget " .. name)
        return nil
    end
    local w = kind(self.scene, e)
    table.insert(self.widgets, w)
    return w
end

local function inside(w, x, y, margin)
    if not w or not w.visible then return false end
    margin = margin or 0
    local p, s = w:getWorldPosition(), w:getWorldScale()
    return x >= p.x - margin and x <= p.x + w.width * s.x + margin and
           y >= p.y - margin and y <= p.y + w.height * s.y + margin
end

local function centre(w)
    local p, s = w:getWorldPosition(), w:getWorldScale()
    return p.x + w.width * s.x / 2, p.y + w.height * s.y / 2
end

function Touch:setActive(active)
    self.active = active
    for _, w in pairs({ self.base, self.runButton, self.flyButton, self.viewButton }) do
        w.visible = active
    end
    if self.help and self.helpKeys then self.help.text = active and HELP_TOUCH or self.helpKeys end
    self:refresh()
    self:publish()
end

-- portrait screens get a narrower UI canvas while the touch controls are on
function Touch:fitCanvas()
    local view = Engine.viewRect
    local portrait = self.active and view.height > view.width
    if portrait == self.portrait then return end
    self.portrait = portrait
    if portrait then
        Engine.setCanvasSize(PORTRAIT_CANVAS[1], PORTRAIT_CANVAS[2])
    else
        Engine.setCanvasSize(self.canvas[1], self.canvas[2])
    end
    -- the UI camera takes the new canvas (older Doriax builds only update it when the window changes)
    self.scene:updateCameraSize()
end

-- what a new finger does, by where it lands
function Touch:startFinger(x, y)
    local walker = CasaWalker
    if self.active then
        if inside(self.base, x, y, 60) then
            return { role = "stick", x = x, y = y, dx = 0, dy = 0 }
        end
        for _, b in ipairs({ { self.runButton, "run" }, { self.flyButton, "fly" }, { self.viewButton, "view" } }) do
            if inside(b[1], x, y, 8) then return { role = "tap", target = b[1], action = b[2], x = x, y = y } end
        end
        if walker and walker.flying then
            if inside(self.upButton, x, y, 8) then return { role = "up" } end
            if inside(self.downButton, x, y, 8) then return { role = "down" } end
        end
    end
    for _, w in ipairs(self.uiAreas) do
        if inside(w, x, y) then return { role = "ui" } end
    end
    return { role = "look", x = x, y = y }
end

function Touch:moveFinger(f, x, y)
    if f.role == "stick" then
        local cx, cy = centre(self.base)
        local dx, dy = x - cx, y - cy
        local len = math.sqrt(dx * dx + dy * dy)
        if len > STICK_RANGE then dx, dy = dx * STICK_RANGE / len, dy * STICK_RANGE / len end
        if self.knob then self.knob.positionOffset = Vector2(dx, dy) end
        f.dx, f.dy = dx / STICK_RANGE, dy / STICK_RANGE
        if math.sqrt(f.dx * f.dx + f.dy * f.dy) < DEAD_ZONE then f.dx, f.dy = 0, 0 end
    elseif f.role == "look" then
        if CasaWalker and (x ~= f.x or y ~= f.y) then CasaWalker:look(x - f.x, y - f.y, LOOK_SPEED) end
        f.x, f.y = x, y
    elseif f.role == "tap" then
        f.x, f.y = x, y
    end
end

function Touch:endFinger(f)
    if f.role == "stick" then
        if self.knob then self.knob.positionOffset = Vector2(0, 0) end
    elseif f.role == "tap" and inside(f.target, f.x, f.y, 8) then
        local walker = CasaWalker
        if f.action == "run" then
            self.running = not self.running
        elseif walker and f.action == "fly" then
            walker:toggleFly()
        elseif walker and f.action == "view" then
            walker:goTo(walker.viewIndex % #walker.views + 1)
        end
    end
end

-- the joystick, run and up/down state for the Walker
function Touch:publish()
    local walker = CasaWalker
    if not walker then return end
    local sx, sy, vertical = 0, 0, 0
    for _, f in pairs(self.fingers) do
        if f.role == "stick" then
            sx, sy = f.dx, f.dy
        elseif f.role == "up" then
            vertical = vertical + 1
        elseif f.role == "down" then
            vertical = vertical - 1
        end
    end
    walker.touchX, walker.touchY = sx, -sy          -- screen y grows downwards; pushing up walks forward
    walker.touchRun = self.active and self.running
    walker.touchVertical = vertical
end

-- button colours, the up/down pair while flying, and the next viewpoint's name
function Touch:refresh()
    local walker = CasaWalker
    local flying = walker and walker.flying or false
    local held = {}
    for _, f in pairs(self.fingers) do held[f.role] = true end
    local function tint(w, on)
        if w then w.color = on and TINT_ON or TINT end
    end
    tint(self.runButton, self.running)
    tint(self.flyButton, flying)
    tint(self.upButton, held.up)
    tint(self.downButton, held.down)
    if self.upButton then self.upButton.visible = self.active and flying end
    if self.downButton then self.downButton.visible = self.active and flying end
    if walker and self.viewText then
        local next = walker.views[walker.viewIndex % #walker.views + 1]
        local label = "Ir para: " .. next.name
        if self.viewText.text ~= label then self.viewText.text = label end
    end
end

function Touch:onUpdate()
    self:fitCanvas()
    local seen = {}
    for _, t in ipairs(Input.getTouches()) do
        local id, pos = t.pointer, t.position
        seen[id] = true
        local f = self.fingers[id]
        if not f then
            f = self:startFinger(pos.x, pos.y)
            self.fingers[id] = f
        end
        self:moveFinger(f, pos.x, pos.y)
    end
    for id, f in pairs(self.fingers) do
        if not seen[id] then
            self:endFinger(f)
            self.fingers[id] = nil
        end
    end
    self:publish()
    self:refresh()
end

return Touch
