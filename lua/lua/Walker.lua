-- Casa Aloisio: first-person walk. Attach to the Camera entity.
-- Collisions use rays against the physics bodies (house collision mesh and terrain height field).
-- On touch screens lua/Touch.lua (HUD scene) drives it through the CasaWalker global: touchX/touchY
-- (joystick, -1..1, y forward), touchRun, touchVertical (flying), look(), toggleFly() and goTo().
-- Game controllers (every connected one, Xbox layout; PlayStation buttons in brackets):
--   left stick walks, right stick looks, RT or L3 runs, Y [triangle] flies, A [cross] / B [circle] go up and
--   down in flight, LB / RB the previous / next viewpoint, D-pad left/right an hour, up/down a day,
--   X [square] the house lights, Start the time panel, Back the sound.
-- World axes: X = east, Y = up, Z = south; yaw 0 looks north (-Z).

local Walker = {
    properties = {
        { name = "eyeHeight", displayName = "Eye height", type = "float", default = 1.62 },
        { name = "walkSpeed", displayName = "Walk speed", type = "float", default = 1.5 },
        { name = "runSpeed", displayName = "Run speed", type = "float", default = 4.0 },
        { name = "flySpeed", displayName = "Fly speed", type = "float", default = 12.0 },
        { name = "startYaw", displayName = "Start yaw (deg, 0 = north)", type = "float", default = 120.0 },
        { name = "startPitch", displayName = "Start pitch (deg)", type = "float", default = -4.0 },
        { name = "mouseSensitivity", displayName = "Mouse sensitivity", type = "float", default = 0.12 },
        { name = "startView", displayName = "Start view (1-6, 0 = entity position)", type = "int", default = 1 },
        { name = "logFps", displayName = "Log FPS every 3 s", type = "bool", default = false },
        { name = "autoWalk", displayName = "Walk test: follow the route and log it", type = "bool", default = false },
        { name = "spinTest", displayName = "Performance test: turn in place", type = "bool", default = false },
    }
}

-- viewpoints (keys 1-6): x, z, yaw (deg, 0 = north), pitch (deg), flying height (nil = on the ground)
local VIEWS = {
    { name = "Rua", x = -25.0, z = -0.1, yaw = 76, pitch = -5 },
    { name = "Entrada", x = -6.62, z = -1.89, yaw = 145, pitch = -2 },
    { name = "Sala", x = 1.23, z = -2.47, yaw = 145, pitch = -6 },
    { name = "Varanda", x = 2.28, z = 1.67, yaw = 145, pitch = -8 },
    { name = "Vista aérea", x = -40, z = -60, yaw = 145, pitch = -25, fly = 85 },
    { name = "Quintal", x = 8.0, z = 11.5, yaw = 325, pitch = 6 },
}

-- walk test (autoWalk): street, gate, service entrance, kitchen, living room, porch, back in and the WC
local AUTO_ROUTE = {
    { x = -11.15, z = -8.42, name = "rua, diante da porteira" },
    { x = -9.44, z = -5.96, name = "porteira" },
    { x = -6.10, z = -1.15, name = "caminho, antes do vão" },
    { x = -5.62, z = -0.46, name = "vão da entrada de serviço" },
    { x = -4.58, z = -0.14, name = "área de serviço" },
    { x = -4.31, z = -0.45, name = "porta D2 (lado serviço)" },
    { x = -3.90, z = -0.73, name = "porta D2" },
    { x = -3.48, z = -0.83, name = "canto da cozinha" },
    { x = -2.83, z = -1.11, name = "cozinha" },
    { x = -1.66, z = -1.19, name = "entre cozinha e mesa" },
    { x = 1.52, z = -0.73, name = "sala, entre sofá e mesa" },
    { x = 1.88, z = 0.06, name = "diante da porta D1" },
    { x = 2.03, z = 0.62, name = "porta D1" },
    { x = 2.64, z = 1.66, name = "varanda" },
    { x = 1.98, z = 0.54, name = "volta pela porta D1" },
    { x = 1.57, z = -0.58, name = "sala" },
    { x = -0.98, z = 1.19, name = "abaixo da geladeira" },
    { x = -1.42, z = 2.05, name = "diante da porta D3" },
    { x = -1.83, z = 2.33, name = "porta D3" },
    { x = -2.29, z = 3.08, name = "WC" },
}

local STRIDE_WALK, STRIDE_RUN = 0.72, 0.95   -- metres between footstep sounds

local PAD_DEAD = 0.15        -- stick dead zone (analog noise)
local PAD_LOOK = 150         -- degrees per second with the right stick fully over (vertical: 65% of it)

local RADIUS = 0.22          -- body radius kept from walls (half a shoulder width)
local STEP = 0.42            -- highest step climbed without jumping
local GRAVITY = 9.8

local sin, cos, rad = math.sin, math.cos, math.rad

function Walker:init()
    self.camera = Camera(self.scene, self.entity)
    local p = self.camera.position
    self.feet = Vector3(p.x, p.y - self.eyeHeight, p.z)
    self.yaw = rad(self.startYaw)
    self.pitch = rad(self.startPitch)
    self.vy = 0
    self.flying = false
    self.looking = false
    self.captured = false      -- Tab: the mouse looks around without holding a button
    self.lastMouse = nil
    self.views = VIEWS
    self.viewIndex = 1
    self.touchX, self.touchY, self.touchRun, self.touchVertical = 0, 0, false, 0
    Engine.mouseMode = MouseMode.NORMAL
    if self.startView >= 1 and self.startView <= #VIEWS then
        self:goTo(self.startView)
    else
        -- from the entity position: on the floor right below it (so it can start indoors, under a roof),
        -- or flying when it is well above the ground
        local g = self:groundBelow(p.x, p.z, p.y, 1000)
        if g and p.y - g > 20 then
            self.flying = true
            self.feet = Vector3(p.x, p.y, p.z)
        elseif g then
            self.feet = Vector3(p.x, g, p.z)
        else
            self:snapToGround(true)
        end
        self:updateCamera()
    end
    self:loadSteps()
    RegisterEngineEvent(self, "onUpdate")
    RegisterEngineEvent(self, "onMouseMove")
    RegisterEngineEvent(self, "onMouseDown")
    RegisterEngineEvent(self, "onMouseUp")
    RegisterEngineEvent(self, "onKeyDown")
    RegisterEngineEvent(self, "onGamepadButtonDown")
    CasaWalker = self
end

-- footsteps: tile inside the house and on the porch (the house collision), grass and earth outside
function Walker:loadSteps()
    self.steps = { piso = {}, grama = {} }
    for kind, list in pairs(self.steps) do
        for i = 1, 6 do
            local s = Sound(self.scene)
            s:loadSound(string.format("sounds/passo_%s_%d.ogg", kind, i))
            table.insert(list, s)
        end
    end
    self.houseBody = self.scene:findEntity("house_collision")
    self.stepAccum, self.lastStep = 0, 0
end

function Walker:footstep(run)
    local list = (self.groundBody == self.houseBody) and self.steps.piso or self.steps.grama
    local i = math.random(#list - 1)
    if i >= self.lastStep then i = i + 1 end           -- never the same sample twice in a row
    self.lastStep = i
    local s = list[i]
    if CasaAmbience and CasaAmbience.muted then return end
    s.volume = (run and 0.75 or 0.55) * (0.85 + 0.3 * math.random())
    s.speed = 0.94 + 0.12 * math.random()
    s:play()
end

function Walker:goTo(i)
    local v = VIEWS[i]
    if not v then return end
    self.viewIndex = i
    self.yaw, self.pitch = rad(v.yaw), rad(v.pitch)
    self.vy = 0
    if v.fly then
        self.flying = true
        self.feet = Vector3(v.x, v.fly, v.z)
    else
        self.flying = false
        -- start on the highest floor below 40 m above the house floor (avoids landing on the roof)
        local g = self:groundBelow(v.x, v.z, 37.0)
        if not g then g = self:groundBelow(v.x, v.z, 300.0, 400) end
        if g then
            self.feet = Vector3(v.x, g, v.z)
            self.pendingView = nil
        else
            -- the terrain and the house are not in the physics world yet (the web build loads them
            -- after the first frames): hold the view and try again next frame instead of falling
            self.feet = Vector3(v.x, 35.0, v.z)
            self.pendingView = i
        end
    end
    self:updateCamera()
end

-- ------------------------------------------------------------------ rays
function Walker:ray(origin, dir, length)
    local r = Ray(origin, Vector3(dir.x * length, dir.y * length, dir.z * length))
    local hit = r:intersects(self.scene, RayFilter.BODY_3D)
    if hit.hit then return hit end
    return nil
end

function Walker:groundBelow(x, z, fromY, length)
    local hit = self:ray(Vector3(x, fromY, z), Vector3(0, -1, 0), length or 60)
    if hit then return hit.point.y, hit.normal, hit.body end
    return nil
end

function Walker:snapToGround(force)
    local g = self:groundBelow(self.feet.x, self.feet.z, self.feet.y + 40)
    if g and (force or g > self.feet.y) then self.feet = Vector3(self.feet.x, g, self.feet.z) end
end

-- blocked by a wall? returns the hit normal of the nearest blocking ray
function Walker:wallHit(from, dir, dist)
    local best = nil
    for _, h in ipairs({ STEP + 0.08, 1.0, 1.55 }) do
        for _, a in ipairs({ 0, 0.6, -0.6 }) do
            local c, s = cos(a), sin(a)
            local d = Vector3(dir.x * c - dir.z * s, 0, dir.x * s + dir.z * c)
            local hit = self:ray(Vector3(from.x, from.y + h, from.z), d, dist + RADIUS)
            if hit and math.abs(hit.normal.y) < 0.7 and (not best or hit.distance < best.distance) then
                best = hit
            end
        end
    end
    return best
end

-- ------------------------------------------------------------------ input
function Walker:onKeyDown(key, repeated, mods)
    if repeated then return end
    if key == Input.KEY_TAB then
        self.captured = not self.captured
        Engine.mouseMode = self.captured and MouseMode.CAPTURED or MouseMode.NORMAL
        self.lastMouse = nil
    elseif key >= Input.KEY_1 and key <= Input.KEY_6 then
        self:goTo(key - Input.KEY_1 + 1)
    elseif key == Input.KEY_F then
        self:toggleFly()
    end
end

function Walker:toggleFly()
    -- flying keeps the eye where it is: in flight feet is the eye itself
    self.flying = not self.flying
    self.vy = 0
    if self.flying then
        self.feet = Vector3(self.feet.x, self.feet.y + self.eyeHeight, self.feet.z)
    else
        self.feet = Vector3(self.feet.x, self.feet.y - self.eyeHeight, self.feet.z)
        self:snapToGround(false)
    end
end

-- ------------------------------------------------------------------ game controllers
local function stick(id, axis)
    local v = Input.getGamepadAxis(id, axis)
    local a = math.abs(v)
    if a < PAD_DEAD then return 0 end
    return (v > 0 and 1 or -1) * math.min(1, (a - PAD_DEAD) / (1 - PAD_DEAD))
end

-- sticks, run and up/down of every connected controller (the ids are sparse: map them by index)
function Walker:readGamepads()
    local pad = { x = 0, y = 0, lookX = 0, lookY = 0, run = false, vertical = 0 }
    for i = 0, Input.numGamepads() - 1 do
        local id = Input.getGamepadId(i)
        if id >= 0 then
            pad.x = pad.x + stick(id, Input.GAMEPAD_AXIS_LEFT_X)
            pad.y = pad.y - stick(id, Input.GAMEPAD_AXIS_LEFT_Y)            -- the Y axes grow downwards
            pad.lookX = pad.lookX + stick(id, Input.GAMEPAD_AXIS_RIGHT_X)
            pad.lookY = pad.lookY + stick(id, Input.GAMEPAD_AXIS_RIGHT_Y)
            -- triggers rest at -1
            if Input.getGamepadAxis(id, Input.GAMEPAD_AXIS_RIGHT_TRIGGER) > 0 or
               Input.isGamepadButtonPressed(id, Input.GAMEPAD_BUTTON_LEFT_THUMB) then
                pad.run = true
            end
            if Input.isGamepadButtonPressed(id, Input.GAMEPAD_BUTTON_A) then pad.vertical = pad.vertical + 1 end
            if Input.isGamepadButtonPressed(id, Input.GAMEPAD_BUTTON_B) then pad.vertical = pad.vertical - 1 end
        end
    end
    return pad
end

function Walker:onGamepadButtonDown(id, button)
    local env, panel, sound = CasaEnvironment, CasaPanel, CasaAmbience
    if button == Input.GAMEPAD_BUTTON_Y then
        self:toggleFly()
    elseif button == Input.GAMEPAD_BUTTON_RIGHT_BUMPER then
        self:goTo(self.viewIndex % #VIEWS + 1)
    elseif button == Input.GAMEPAD_BUTTON_LEFT_BUMPER then
        self:goTo((self.viewIndex - 2) % #VIEWS + 1)
    elseif button == Input.GAMEPAD_BUTTON_DPAD_RIGHT then
        if env then env:addHours(1) end
    elseif button == Input.GAMEPAD_BUTTON_DPAD_LEFT then
        if env then env:addHours(-1) end
    elseif button == Input.GAMEPAD_BUTTON_DPAD_UP then
        if env then env:addDays(1) end
    elseif button == Input.GAMEPAD_BUTTON_DPAD_DOWN then
        if env then env:addDays(-1) end
    elseif button == Input.GAMEPAD_BUTTON_X then
        if env then env:cycleLights() end
    elseif button == Input.GAMEPAD_BUTTON_START then
        if panel then panel:setVisible(not panel.visible) end
    elseif button == Input.GAMEPAD_BUTTON_BACK then
        if sound then sound.muted = not sound.muted end
    end
end

-- turns the view by a pointer movement of dx, dy (degrees per unit)
function Walker:look(dx, dy, sensitivity)
    self.yaw = self.yaw + rad(dx * sensitivity)
    self.pitch = math.max(rad(-85), math.min(rad(85), self.pitch - rad(dy * sensitivity)))
    self:updateCamera()
end

function Walker:onMouseDown(button, x, y, mods)
    if button == Input.MOUSE_BUTTON_RIGHT then
        self.looking = true
        self.lastMouse = nil
    end
end

function Walker:onMouseUp(button, x, y, mods)
    if button == Input.MOUSE_BUTTON_RIGHT then self.looking = false end
end

function Walker:onMouseMove(x, y, mods)
    local active = self.captured or self.looking
    if active and self.lastMouse then
        self:look(x - self.lastMouse.x, y - self.lastMouse.y, self.mouseSensitivity)
    end
    self.lastMouse = Vector2(x, y)
end

-- ------------------------------------------------------------------ movement
function Walker:onUpdate()
    if self.pendingView then
        self:goTo(self.pendingView)
        return
    end
    if self.logFps then
        self.fpsTime = (self.fpsTime or 0) + Engine.deltatime
        self.fpsFrames = (self.fpsFrames or 0) + 1
        if self.fpsTime >= 3 then
            print(string.format("FPS %.1f (%.1f ms) at %.1f %.1f %.1f", self.fpsFrames / self.fpsTime,
                1000 * self.fpsTime / self.fpsFrames, self.feet.x, self.feet.y, self.feet.z))
            self.fpsTime, self.fpsFrames = 0, 0
        end
    end
    local dt = math.min(Engine.deltatime, 0.05)
    local pad = self:readGamepads()
    if pad.lookX ~= 0 or pad.lookY ~= 0 then
        -- squared response: small pushes aim finely, a full push turns fast
        self:look(pad.lookX * math.abs(pad.lookX) * PAD_LOOK * dt, pad.lookY * math.abs(pad.lookY) * PAD_LOOK * 0.65 * dt, 1)
    end
    local fx, fz = sin(self.yaw), -cos(self.yaw)
    local mx, mz = 0, 0
    if Input.isKeyPressed(Input.KEY_W) or Input.isKeyPressed(Input.KEY_UP) then mx, mz = mx + fx, mz + fz end
    if Input.isKeyPressed(Input.KEY_S) or Input.isKeyPressed(Input.KEY_DOWN) then mx, mz = mx - fx, mz - fz end
    if Input.isKeyPressed(Input.KEY_D) or Input.isKeyPressed(Input.KEY_RIGHT) then mx, mz = mx - fz, mz + fx end
    if Input.isKeyPressed(Input.KEY_A) or Input.isKeyPressed(Input.KEY_LEFT) then mx, mz = mx + fz, mz - fx end
    -- touch joystick and controller stick: analog, a short push walks slowly
    local ax, ay = self.touchX + pad.x, self.touchY + pad.y
    local analog = 1
    if ax ~= 0 or ay ~= 0 then
        mx = mx + fx * ay - fz * ax
        mz = mz + fz * ay + fx * ax
        analog = math.min(1, math.sqrt(ax * ax + ay * ay))
    end
    if self.autoWalk then
        mx, mz = self:autoStep(dt)
    end
    if self.spinTest then
        self.yaw = self.yaw + rad(30) * dt
        self:updateCamera()
    end
    local len = math.sqrt(mx * mx + mz * mz)
    local run = Input.isKeyPressed(Input.KEY_LEFT_SHIFT) or Input.isKeyPressed(Input.KEY_RIGHT_SHIFT) or self.touchRun or pad.run

    if self.flying then
        local speed = self.flySpeed * (run and 3 or 1)
        local vy = self.touchVertical + pad.vertical
        if Input.isKeyPressed(Input.KEY_SPACE) or Input.isKeyPressed(Input.KEY_E) then vy = vy + 1 end
        if Input.isKeyPressed(Input.KEY_C) or Input.isKeyPressed(Input.KEY_Q) then vy = vy - 1 end
        if len > 0 then mx, mz = mx / len * analog, mz / len * analog end
        local cp = cos(self.pitch)
        self.feet = Vector3(self.feet.x + mx * speed * dt, self.feet.y + (vy + (len > 0 and sin(self.pitch) * (mx * fx + mz * fz) or 0)) * speed * dt,
                            self.feet.z + mz * speed * dt)
        self:updateCamera()
        return
    end

    if len > 0 then
        local speed = (run and self.runSpeed or self.walkSpeed) * analog
        local dist = speed * dt
        local dir = Vector3(mx / len, 0, mz / len)
        local hit = self:wallHit(self.feet, dir, dist)
        if hit then
            -- slide along the wall: drop the part of the motion that goes into it
            local n = Vector3(hit.normal.x, 0, hit.normal.z)
            local nl = math.sqrt(n.x * n.x + n.z * n.z)
            if nl > 0 then n = Vector3(n.x / nl, 0, n.z / nl) end
            local into = dir.x * n.x + dir.z * n.z
            dir = Vector3(dir.x - n.x * into, 0, dir.z - n.z * into)
            local dl = math.sqrt(dir.x * dir.x + dir.z * dir.z)
            if dl > 0.05 then
                dir = Vector3(dir.x / dl, 0, dir.z / dl)
                if self:wallHit(self.feet, dir, dist * dl) then dl = 0 end
            end
            dist = dist * dl
        end
        if dist > 0 then
            local nx, nz = self.feet.x + dir.x * dist, self.feet.z + dir.z * dist
            local g = self:groundBelow(nx, nz, self.feet.y + STEP + 0.05)
            if g and g <= self.feet.y + STEP then
                self.feet = Vector3(nx, self.feet.y, nz)
                self.stepAccum = self.stepAccum + dist
            elseif not g then
                self.feet = Vector3(nx, self.feet.y, nz)
            end
            if self.stepAccum >= (run and STRIDE_RUN or STRIDE_WALK) then
                self.stepAccum = 0
                self:footstep(run)
            end
        end
    end

    -- gravity and steps
    local g, _, body = self:groundBelow(self.feet.x, self.feet.z, self.feet.y + STEP + 0.05)
    self.groundBody = body
    if g and g >= self.feet.y - 0.02 then
        -- on the ground or climbing a step: ease up instead of popping
        local up = g - self.feet.y
        self.feet = Vector3(self.feet.x, self.feet.y + math.min(up, math.max(0.02, up * math.min(1, dt * 14))), self.feet.z)
        self.vy = 0
    else
        self.vy = self.vy - GRAVITY * dt
        local ny = self.feet.y + self.vy * dt
        if g and ny <= g then ny = g; self.vy = 0 end
        self.feet = Vector3(self.feet.x, ny, self.feet.z)
    end
    self:updateCamera()
end

-- walk test: heads for the next route point as if W were held, and logs progress, falls and where it gets stuck
function Walker:autoStep(dt)
    if not self.autoIndex then
        self.autoIndex, self.autoClock, self.autoCheck = 1, 0, Vector3(self.feet.x, self.feet.y, self.feet.z)
        print("AUTOWALK start at " .. string.format("%.2f %.2f %.2f", self.feet.x, self.feet.y, self.feet.z))
    end
    local target = AUTO_ROUTE[self.autoIndex]
    if not target then return 0, 0 end
    local dx, dz = target.x - self.feet.x, target.z - self.feet.z
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist < 0.3 then
        print(string.format("AUTOWALK ok %d/%d %s (y %.2f)", self.autoIndex, #AUTO_ROUTE, target.name, self.feet.y))
        self.autoIndex = self.autoIndex + 1
        if self.autoIndex > #AUTO_ROUTE then print("AUTOWALK DONE: every point reached") end
        return 0, 0
    end
    self.yaw = math.atan(dx, -dz)
    self:updateCamera()
    self.autoClock = self.autoClock + dt
    if self.autoClock > 2.0 then
        local moved = math.sqrt((self.feet.x - self.autoCheck.x) ^ 2 + (self.feet.z - self.autoCheck.z) ^ 2)
        local drop = self.autoCheck.y - self.feet.y
        if drop > 0.8 then
            print(string.format("AUTOWALK fall of %.2f m before %s", drop, target.name))
        end
        if moved < 0.2 then
            print(string.format("AUTOWALK STUCK before %d %s at %.2f %.2f %.2f, %.2f m away", self.autoIndex, target.name,
                self.feet.x, self.feet.y, self.feet.z, dist))
            local dir = Vector3(dx / dist, 0, dz / dist)
            local hit = self:wallHit(self.feet, dir, 0.1)
            if hit then
                print(string.format("AUTOWALK   wall hit at %.2f %.2f %.2f normal %.2f %.2f %.2f distance %.2f", hit.point.x, hit.point.y,
                    hit.point.z, hit.normal.x, hit.normal.y, hit.normal.z, hit.distance))
            end
            local ahead = self:groundBelow(self.feet.x + dir.x * 0.3, self.feet.z + dir.z * 0.3, self.feet.y + 3)
            print(string.format("AUTOWALK   ground 0.3 m ahead %s (feet %.2f)", ahead and string.format("%.2f", ahead) or "none", self.feet.y))
            self.autoIndex = #AUTO_ROUTE + 1
            return 0, 0
        end
        self.autoClock, self.autoCheck = 0, Vector3(self.feet.x, self.feet.y, self.feet.z)
    end
    return dx / dist, dz / dist
end

function Walker:updateCamera()
    local eye = Vector3(self.feet.x, self.feet.y + (self.flying and 0 or self.eyeHeight), self.feet.z)
    local cp = cos(self.pitch)
    local look = Vector3(sin(self.yaw) * cp, sin(self.pitch), -cos(self.yaw) * cp)
    self.camera.position = eye
    self.camera.target = Vector3(eye.x + look.x, eye.y + look.y, eye.z + look.z)
end

return Walker
