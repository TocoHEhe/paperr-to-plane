--[[ DYXNET // PAPER.OPS  —  Paper To Plane (place 132583639194663) — v1
     Talks to the server directly (no gamepass needed):
       Farm    : SUPER THROW (direct ChargeBegin/Release @0.756 s) + auto-dodge + ring seeking, auto train best zone
       Upgrade : auto rebirth, auto next world, buy paper, buy stronger planes, auto fold, auto fuse, equip best plane
       Rewards : playtime, daily, community, codes, Halloween candy exchange
     F8 = stop all · RightShift = show/hide · reload-safe. Contracts measured 2026-11-14 on PlaceVersion 2705 (see GAME_NOTES.md). ]]

if not game:IsLoaded() then game.Loaded:Wait() end
assert(game.PlaceId == 132583639194663, "DYXNET: wrong game")

local Players, RS, UIS, Run, Tween, Http = game:GetService("Players"), game:GetService("ReplicatedStorage"),
    game:GetService("UserInputService"), game:GetService("RunService"), game:GetService("TweenService"), game:GetService("HttpService")
local lp = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
-- reaching this line means PandAuth verified the key: remove the key gate's "Checking key…" banner and save the key
do
    local pgui = lp:FindFirstChildOfClass("PlayerGui")
    local banner = pgui and pgui:FindFirstChild("PaperToPlanes_KeyCheck")
    if banner then banner:Destroy() end
    if type(env.PaperToPlanes_OnPandaVerified) == "function" then
        pcall(env.PaperToPlanes_OnPandaVerified)
        env.PaperToPlanes_OnPandaVerified = nil
    end
end

-- Panda Vault runs this main file only after PUSL-V4 verifies the key.
-- The separate key GUI stages this callback only when "Remember key" is enabled.
local afterVerify = env.PaperToPlanes_OnPandaVerified
env.PaperToPlanes_OnPandaVerified = nil
if type(afterVerify) == "function" then pcall(afterVerify) end

local restore = {}
if type(env.DYX_PaperOps_Close) == "function" then
    local ok, prev = pcall(env.DYX_PaperOps_Close)
    if ok and type(prev) == "table" then restore = prev end
end

local R = RS:WaitForChild("PaperPlaneRemotes")
local Shared = RS:WaitForChild("PaperPlaneShared")
local PlaneFlight, TrainingRE = R:WaitForChild("PlaneFlight"), R:WaitForChild("Training")
local Cfg = {}
for _, n in ipairs({"SmartFlightConfig", "RingConfig", "FlightSteering", "TrainingConfig", "PlaneConfig", "PaperFoldingConfig",
    "WorldPortalConfig", "DailyRewardConfig", "WorldGateConfig", "HazardSystem", "FlightConfig"}) do
    local m = Shared:FindFirstChild(n)
    if m then local ok, v = pcall(require, m) if ok then Cfg[n] = v end end
end

local S = {                     -- shared runtime state
    alive = true, gateLocked = false, on = {}, token = 0, log = {}, status = "Sẵn sàng",
    -- user choices from the dropdowns (saved to DYX_paper_opts.json)
    opt = {buyPaper = {Uncommon = true, Rare = true, Epic = true, Legendary = true, Mythical = true},
        fold = {Uncommon = true, Rare = true, Epic = true, Legendary = true, Mythical = true},
        event = {}, fuse = "auto", unlock = "auto", farm = "auto"},
    conns = {}, profile = nil, attemptNext = 0, trainSeq = 1000 + math.random(1, 500),
    stats = {throws = 0, rings = 0, coins = 0, folds = 0, fuses = 0, crashes = 0},
}
local function on(sig, fn) local c = sig:Connect(fn) S.conns[#S.conns + 1] = c return c end
local OPT_FILE = "DYX_paper_opts.json"
pcall(function()
    local saved = Http:JSONDecode(readfile(OPT_FILE))
    if type(saved) == "table" then for k, v in pairs(saved) do S.opt[k] = v end end
end)
local function saveOpt() pcall(writefile, OPT_FILE, Http:JSONEncode(S.opt)) end
-- language: "en" (default on first run) or "vi"; the user's choice is saved in DYX_paper_opts.json
if S.opt.lang ~= "vi" then S.opt.lang = "en" end
local function tr(vi, en) return S.opt.lang == "en" and en or vi end
local RARITIES = {"Mythical", "Legendary", "Epic", "Rare", "Uncommon"}
local function now() return os.clock() end
local function say(msg)
    S.status = msg
    local line = os.date("%H:%M:%S ") .. msg
    S.log[#S.log + 1] = line
    if #S.log > 400 then table.remove(S.log, 1) end
    S.pendingLog = S.pendingLog or {}
    S.pendingLog[#S.pendingLog + 1] = line
    if S.onStatus then pcall(S.onStatus, msg) end
end
-- log is appended across runs (previous run kept), flushed every 5 s
local LOG_FILE = "DYX_paper_ops_log.txt"
pcall(function()
    local old = isfile and isfile(LOG_FILE) and readfile(LOG_FILE) or ""
    if #old > 60000 then old = old:sub(-30000) end
    writefile(LOG_FILE, old .. "\n===== RUN " .. os.date("%Y-%m-%d %H:%M:%S") .. " =====\n")
end)
local function flushLog()
    local pend = S.pendingLog
    if not pend or #pend == 0 then return end
    S.pendingLog = {}
    local chunk = table.concat(pend, "\n") .. "\n"
    if appendfile then pcall(appendfile, LOG_FILE, chunk)
    else pcall(function() writefile(LOG_FILE, (readfile(LOG_FILE) or "") .. chunk) end) end
end
task.spawn(function()
    while S.alive do task.wait(5) flushLog() end
end)

-- ============================================================ CORE HELPERS
local G = {}
do
    function G.call(name, ...)
        local r = R:FindFirstChild(name)
        if not (r and r:IsA("RemoteFunction")) then return {ok = false, msg = "missing " .. name} end
        local ok, res = pcall(r.InvokeServer, r, ...)
        if not ok then return {ok = false, msg = tostring(res)} end
        return type(res) == "table" and res or {ok = res == true, value = res}
    end
    function G.fold(action, ...) return G.call("PaperFolding", action, ...) end
    function G.attr(k) return lp:GetAttribute(k) end
    function G.world() return tonumber(lp:GetAttribute("CurrentWorld")) or 1 end
    function G.abbrev(n)
        n = tonumber(n) or 0
        for _, u in ipairs({{1e12, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "K"}}) do if n >= u[1] then return string.format("%.2f%s", n / u[1], u[2]) end end
        return tostring(math.floor(n))
    end
    function G.coins() local ls = lp:FindFirstChild("leaderstats") local c = ls and ls:FindFirstChild("Coins") return c and c.Value or 0 end
    function G.char() local c = lp.Character return c, c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid") end
    function G.alive(token) return S.alive and token == S.token end
    -- the game's folding client anchors the character and opens "Choose your paper" when we Enter a table;
    -- an anchored root never replicates, so the server keeps us at the table. Close it the way the X button does.
    local endFoldingFn
    function G.leaveFolding()
        local _, root, hum = G.char()
        if not endFoldingFn and getgc then
            for _, fn in ipairs(getgc(false)) do
                if type(fn) == "function" and islclosure(fn) then
                    local okN, nm = pcall(debug.info, fn, "n")
                    if okN and nm == "endFolding" then
                        local okS, src = pcall(debug.info, fn, "s")
                        if okS and tostring(src):find("PaperFolding") then endFoldingFn = fn break end
                    end
                end
            end
        end
        if endFoldingFn then pcall(endFoldingFn) end
        if root and root.Anchored then root.Anchored = false end
        if hum then
            if hum.WalkSpeed < 8 then hum.WalkSpeed = 16 end
            if hum.UseJumpPower and hum.JumpPower < 1 then hum.JumpPower = 50 end
            if not hum.UseJumpPower and hum.JumpHeight < 1 then hum.JumpHeight = 7.2 end
            hum.AutoRotate = true
        end
        local cam = workspace.CurrentCamera
        if cam and cam.CameraType == Enum.CameraType.Scriptable then
            cam.CameraType = Enum.CameraType.Custom
            if hum then cam.CameraSubject = hum end
        end
    end
    function G.tp(cf, settle)
        local _, root, hum = G.char()
        if not root then return false end
        if root.Anchored or (hum and hum.WalkSpeed < 1) then G.leaveFolding() task.wait(0.2) end
        -- folding seats the character at the table: get up first, or the server keeps us pinned to the seat
        if hum and (hum.SeatPart or hum.Sit) then
            hum.Sit = false
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
            local t = os.clock()
            while hum.SeatPart and os.clock() - t < 1.5 do task.wait(0.05) end
            task.wait(0.2)
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = typeof(cf) == "Vector3" and CFrame.new(cf) or cf
        task.wait(settle or 0.35)
        return true
    end
    function G.pivot(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.CFrame end
        if inst:IsA("Model") then return inst:GetPivot() end
        local p = inst:FindFirstChildWhichIsA("BasePart", true)
        return p and p.CFrame
    end
    function G.path(...)
        local o = workspace
        for _, n in ipairs({...}) do o = o and o:FindFirstChild(n) end
        return o
    end
    function G.gameplay(w) return G.path("World " .. (w or G.world()), "Gameplay") end
    function G.refreshProfile()
        local r = G.call("GetProfile")
        if r.ok and type(r.data) == "table" then S.profile = r.data end
        return S.profile
    end
    local pc = R:FindFirstChild("ProfileChanged")
    if pc then on(pc.OnClientEvent, function(p) if type(p) == "table" then S.profile = p end end) end
    task.spawn(G.refreshProfile)
    function G.equipTool()
        local c, _, hum = G.char()
        if c and hum and not c:FindFirstChildOfClass("Tool") then
            local t = lp.Backpack:FindFirstChild("Paper Plane")
            if t then hum:EquipTool(t) task.wait(0.2) end
        end
    end
    -- plane strength heuristic (BasePlanePower, stars) for "best plane"
    -- BasePlanePower is the "+25 / +66" number the game shows on plane cards (verified: CyberDevil = 25 in Launched stats)
    function G.planeScore(p)
        local cfg = Cfg.PlaneConfig and Cfg.PlaneConfig.Get(p.Id)
        local base = cfg and (tonumber(cfg.BasePlanePower) or 0) or 0
        return base * (1 + 0.12 * (tonumber(p.StarLevel) or 0)) + 0.001 * (cfg and tonumber(cfg.CoinsMultiplier) or 1)
    end
    function G.planeLabel(p)
        local cfg = Cfg.PlaneConfig and Cfg.PlaneConfig.Get(p.Id)
        local name = cfg and (cfg.DisplayName or cfg.PlaneId) or p.Id
        return string.format("%s · +%s · %d★%s%s", tostring(name), tostring(cfg and cfg.BasePlanePower or "?"),
            tonumber(p.StarLevel) or 0, (tonumber(p.Quantity) or 1) > 1 and (" ×" .. p.Quantity) or "", p.Equipped and " · đang dùng" or "")
    end
    function G.bestPlane()
        local best, bs
        for _, p in ipairs((S.profile and S.profile.Planes) or {}) do
            local s = G.planeScore(p)
            if not bs or s > bs then best, bs = p, s end
        end
        return best, bs
    end
end

-- ============================================================ ANTI-AFK (always on)
-- Roblox disconnects a player after 20 minutes without input ("Idled"). Answer it with a virtual
-- right-click, so long AFK farming sessions are never kicked. Nothing is clicked in the game itself.
do
    local okVU, VU = pcall(function() return game:GetService("VirtualUser") end)
    if okVU and VU then
        on(lp.Idled, function()
            pcall(function()
                VU:CaptureController()
                VU:ClickButton2(Vector2.new(0, 0))
            end)
            S.stats.antiAfk = (S.stats.antiAfk or 0) + 1
        end)
    end
end

-- ============================================================ FLIGHT (direct throw + dodge + rings)
local F = {}
do
    local SmartCfg, RingConfig, FlightSteering = Cfg.SmartFlightConfig, Cfg.RingConfig, Cfg.FlightSteering
    local fc = lp:WaitForChild("PlayerScripts"):FindFirstChild("PaperPlaneFlightClient")
    local Smart = fc and fc:FindFirstChild("SmartFlightController") and require(fc.SmartFlightController)
    local Steer = fc and fc:FindFirstChild("PlaneSteeringController") and require(fc.PlaneSteeringController)
    local prefix = tostring(lp.UserId) .. "_"
    local attempt, flight = {}, {id = nil, state = "IDLE", rings = {}, hazards = 0, got = 0}
    local candidates, flights = {}, nil
    for _, fn in ipairs(getgc and getgc(false) or {}) do
        if type(fn) == "function" and islclosure(fn) then
            local okN, nm = pcall(debug.info, fn, "n")
            if okN and nm == "updateFlights" then
                local okU, ups = pcall(debug.getupvalues, fn)
                if okU then for _, v in pairs(ups) do if type(v) == "table" and getmetatable(v) == nil then candidates[#candidates + 1] = v end end end
                break
            end
        end
    end
    -- AssistUntilStage (server update 2845): the game's auto dodge switches itself OFF after stage 5
    -- ("STAGE 5 CLEARED - AUTO DODGE OFF"), so stages 6+ were flown with no auto-pilot at all.
    local saved = {dur = SmartCfg and SmartCfg.AssistDuration, pull = SmartCfg and SmartCfg.HomePull,
        ret = SmartCfg and SmartCfg.ReturnAfterClear, untilStage = SmartCfg and SmartCfg.AssistUntilStage,
        setAssist = Steer and Steer.SetAssist, stop = Smart and Smart.Stop}
    local assistL, assistV, steering, patched = 0, 0, false, false
    -- The game's auto-pilot is handicapped on purpose: later worlds/stages shrink its lookahead and add a
    -- reaction delay (SmartFlightConfig.WorldDifficultyProfiles / StageDifficultyProfiles). Remove that handicap only.
    -- (Widening its margins/lookahead made it worse: it then flew into the new W3 stage-2 obstacle every time.
    --  New obstacles are now handled by our own look-ahead guard below, which reads the game's hazard list.)
    local TUNE = {}
    local savedTune, savedProfiles = {}, nil
    local function tune(onoff)
        if onoff then
            for k, v in pairs(TUNE) do
                if savedTune[k] == nil then savedTune[k] = SmartCfg[k] end
                if SmartCfg[k] ~= nil then SmartCfg[k] = v end
            end
            if not savedProfiles then
                savedProfiles = {w = SmartCfg.WorldDifficultyProfiles, s = SmartCfg.StageDifficultyProfiles}
                local w = {}
                for i = 1, 8 do w[i] = {Lookahead = 1.15, Reaction = 0} end
                SmartCfg.WorldDifficultyProfiles = w
                SmartCfg.StageDifficultyProfiles = {{From = 1, To = 99, Lookahead = 1}}
            end
        else
            for k, v in pairs(savedTune) do SmartCfg[k] = v end
            table.clear(savedTune)
            if savedProfiles then
                SmartCfg.WorldDifficultyProfiles, SmartCfg.StageDifficultyProfiles = savedProfiles.w, savedProfiles.s
                savedProfiles = nil
            end
        end
    end
    function F.patch(onoff)
        if not (Smart and Steer and SmartCfg) or patched == onoff then return end
        patched = onoff
        if onoff then
            SmartCfg.AssistDuration, SmartCfg.HomePull, SmartCfg.ReturnAfterClear = nil, 0.6, 0
            SmartCfg.AssistUntilStage = nil
            pcall(tune, true)
            Steer.SetAssist = function(l, v) assistL, assistV = tonumber(l) or 0, tonumber(v) or 0 return saved.setAssist(l, v) end
            Smart.Stop = function(...) if steering then return end return saved.stop(...) end
            -- The game's PlaneClientController sets the plane's steering from GetAxis()/GetVerticalAxis() every
            -- frame and sends its own "Steer" ~10x/s. While our planner flies, both must say the same thing,
            -- or the server mixes two pilots (measured: plane 2-9 studs off the planned path).
            saved.getAxis, saved.getVAxis = saved.getAxis or Steer.GetAxis, saved.getVAxis or Steer.GetVerticalAxis
            Steer.GetAxis = function(...)
                if steering and F.cmd then return F.cmd[1] end
                return saved.getAxis(...)
            end
            Steer.GetVerticalAxis = function(...)
                if steering and F.cmd then return F.cmd[2] end
                return saved.getVAxis(...)
            end
        else
            if saved.getAxis then Steer.GetAxis, Steer.GetVerticalAxis = saved.getAxis, saved.getVAxis end
            SmartCfg.AssistDuration, SmartCfg.HomePull, SmartCfg.ReturnAfterClear = saved.dur, saved.pull, saved.ret
            SmartCfg.AssistUntilStage = saved.untilStage
            pcall(tune, false)
            Steer.SetAssist, Smart.Stop = saved.setAssist, saved.stop
            pcall(saved.stop)
        end
    end
    -- own flight: World 1 ids look like "<UserId>_<n>", World 2+ ids are GUIDs, so match by UserId / AttemptId / known FlightId
    local function mine(d)
        if type(d) ~= "table" then return false end
        if tonumber(d.UserId) and math.floor(tonumber(d.UserId) + 0.5) == lp.UserId then return true end
        if d.AttemptId ~= nil and attempt[d.AttemptId] ~= nil then return true end
        if d.FlightId ~= nil and d.FlightId == flight.id then return true end
        return type(d.FlightId) == "string" and d.FlightId:sub(1, #prefix) == prefix
    end
    -- flight diagnostics: every server event about us (by AttemptId / UserId / FlightId) goes to the log once per kind+attempt
    local function dump(v, depth)
        depth = depth or 0
        if type(v) ~= "table" then
            if typeof(v) == "Vector3" then return string.format("V(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z) end
            return tostring(v):sub(1, 40)
        end
        if depth > 0 then return "{…}" end
        local p = {}
        for k, x in pairs(v) do p[#p + 1] = tostring(k) .. "=" .. dump(x, depth + 1) if #p > 22 then break end end
        table.sort(p)
        return "{" .. table.concat(p, ", ") .. "}"
    end
    local seenDiag = {}
    on(PlaneFlight.OnClientEvent, function(kind, d)
        if type(d) ~= "table" or kind == "SteeringState" or kind == "RingSpawn" then return end
        local ours = attempt[d.AttemptId] ~= nil or mine(d) or (tonumber(d.UserId) and math.floor(d.UserId + 0.5) == lp.UserId)
        if not ours then return end
        local key = tostring(kind) .. "|" .. tostring(d.AttemptId or d.FlightId)
        if seenDiag[key] then return end
        seenDiag[key] = true
        say("[srv] " .. tostring(kind) .. " " .. dump(d))
    end)
    on(PlaneFlight.OnClientEvent, function(kind, d)
        d = d or {}
        if kind == "ChargeAccepted" or kind == "Rejected" or kind == "Thrown" then
            local a = attempt[d.AttemptId]
            if not a then return end
            if kind == "ChargeAccepted" then a.accepted = true
            elseif kind == "Rejected" then a.result, a.msg, a.next = "REJECTED", d.Msg, d.NextAttemptId
            else
                a.result, a.power, a.tier = "THROWN", d.Power, d.Tier
                flight.state, flight.throwAt = "THROWN", now()
                -- SUPER THROW cutscene: the server holds the launch until the client reports the film ended.
                -- We never play the film (direct throw), so report it right away.
                if d.CinematicSession ~= nil or type(d.Cinematic) == "string" then
                    local session = d.CinematicSession
                    task.delay(0.25, function()
                        PlaneFlight.FireServer(PlaneFlight, "SuperThrowCinematicEnded", session, "completed")
                    end)
                    say(tr("Bỏ qua phim SUPER THROW (", "Skipped SUPER THROW cutscene (") .. tostring(d.Cinematic) .. ")")
                end
            end
            return
        end
        if not mine(d) then return end
        if kind == "Revived" and flight.id and (d.FlightId == flight.id or flight.state == "LANDED") then
            -- REVIVE (update 2845): the crashed flight resumes a little before the crash point, same FlightId,
            -- with a shield. The game rebuilds its flight sim from Resume.Sim, so our steering just carries on.
            local rs = type(d.Resume) == "table" and d.Resume or {}
            flight.id, flight.state = d.FlightId or flight.id, "FLYING"
            flight.start = nil              -- re-measured from the resumed sim (the pause shifted the clock)
            flight.shieldEnds = tonumber(rs.ShieldEndsAt)
            flight.offerUntil = nil
            flight.revived = (flight.revived or 0) + 1
            flight.throwAt = now()
            F.landing = nil                 -- the crash no longer ends this run (gate runs keep counting it as one try)
            pcall(F.patch, true)
            say(string.format(tr("Đã hồi sinh · khiên %ds · bay tiếp", "Revived · %ds shield · flying on"), tonumber(rs.ShieldSeconds) or 5))
            return
        end
        if kind == "Launched" and flight.state == "THROWN" then
            flight.id, flight.state, flight.rings, flight.hazards, flight.got = d.FlightId, "FLYING", {}, 0, 0
            -- server clock at flight sim time 0: hazards (lasers, robots, drones…) run on the server clock
            flight.start = tonumber(d.StartTime)
            flight.shieldEnds, flight.offerUntil, flight.reviveBusy, flight.revived = nil, nil, nil, 0
            flight.candyGot, flight.sim, flight.srv = 0, nil, nil
            return
        end
        if d.FlightId ~= flight.id then return end
        if kind == "RingSpawn" then
            flight.rings[d.RingId] = {Type = d.Type, Along = d.Along, Pos = d.Position, Motion = d.Motion, Right = d.Right}
        elseif kind == "RingCollected" then flight.rings[d.RingId] = nil flight.got += 1 S.stats.rings += 1
        elseif kind == "RingRemoved" then flight.rings[d.RingId] = nil
        elseif kind == "HazardCrash" then flight.hazards += 1 S.stats.crashes += 1
        elseif kind == "Landed" then
            flight.state = "LANDED"
            -- "Hit" = reached the finish gate, "Crash" = hit an obstacle; kept for the unlock planner
            F.landing = {reason = tostring(d.Reason), distance = tonumber(d.Distance) or 0, at = now()}
        elseif kind == "Reward" then
            S.stats.coins += tonumber(d.Reward) or 0
            say(string.format(tr("Lượt bay +%s Coins · %d studs · %d ring%s", "Flight +%s Coins · %d studs · %d rings%s"),tostring(d.Reward), math.floor(tonumber(d.Distance) or 0), tonumber(d.RingsCollected) or 0,
                (flight.candyGot or 0) > 0 and (" · +" .. flight.candyGot .. tr(" kẹo", " candy")) or ""))
        elseif kind == "Returned" then flight.state = "RETURNED" end
    end)
    -- ---- PLANE CRASHED! revive offer (remote "Revive", update 2845) ----
    -- Server: Revive "Offer" {FlightId, DailyFree, Credits, Price, Remaining, Duration, ShieldSeconds, Tier, Max}
    -- Client: Revive:FireServer("Buy", FlightId) / ("Cancel", FlightId)  (exactly what the popup buttons send)
    -- "Buy" is only sent when it costs nothing: the FREE daily revive, or revives already saved on the
    -- account ("SAVED", used on finish-gate runs only). A paid offer is never bought: it is cancelled
    -- right away instead of waiting out the 15 s countdown.
    local ReviveRE = R:FindFirstChild("Revive")
    -- press the game's own popup button (its handler sends the remote AND closes the popup properly);
    -- returns false when that was not possible, then the caller sends the remote itself
    local function pressRevive(name)
        local gui = lp:FindFirstChild("PlayerGui") and lp.PlayerGui:FindFirstChild("ReviveGui")
        local btn = gui and gui:FindFirstChild("Holder") and gui.Holder:FindFirstChild("Card") and gui.Holder.Card:FindFirstChild(name)
        if not (btn and btn:IsA("GuiButton") and type(getconnections) == "function") then return false end
        local fired = 0
        for _, c in ipairs(getconnections(btn.Activated)) do
            if pcall(function() c:Fire() end) then fired += 1 end
        end
        return fired > 0
    end
    if ReviveRE then
        on(ReviveRE.OnClientEvent, function(kind, d)
            if type(d) ~= "table" then return end
            if kind == "Offer" then
                local fid = d.FlightId
                if typeof(fid) ~= "string" then return end
                -- only flights this script threw (manual flights: the player decides)
                if not (flight.id and fid == flight.id) or not ((S.on.throw or S.on.candy) or S.on.unlock) then return end
                flight.reviveBusy = nil
                local credits = tonumber(d.Credits) or 0
                local free = d.DailyFree == true and "daily" or (credits > 0 and S.gateMode and "saved") or nil
                flight.offerUntil = now() + math.max(1, tonumber(d.Remaining) or 15) + 1
                task.delay(0.4 + math.random() * 0.3, function()
                    if not S.alive or flight.id ~= fid then return end
                    if free then
                        if not pressRevive("Revive") then ReviveRE.FireServer(ReviveRE, "Buy", fid) end
                        say(free == "daily" and tr("Máy bay rơi — dùng lượt HỒI SINH MIỄN PHÍ hằng ngày", "Plane crashed — using the FREE daily revive")
                            or string.format(tr("Máy bay rơi (lượt tới cổng) — dùng hồi sinh đã lưu (còn %d)", "Plane crashed (gate run) — using a saved revive (%d left)"), credits))
                        task.delay(2.5, function()    -- popup handler refused (busy/debounce): send it ourselves once
                            if S.alive and flight.offerUntil and not flight.reviveBusy and flight.id == fid and flight.state ~= "FLYING" then
                                ReviveRE.FireServer(ReviveRE, "Buy", fid)
                            end
                        end)
                        task.delay(7, function()      -- still no answer: stop waiting, the scheduler takes over
                            if flight.offerUntil and flight.id == fid and flight.state ~= "FLYING" then flight.offerUntil = now() + 1 end
                        end)
                    else
                        if not pressRevive("Cancel") then ReviveRE.FireServer(ReviveRE, "Cancel", fid) end
                        flight.offerUntil = now() + 1
                        say(string.format(tr("Máy bay rơi — bỏ qua hồi sinh trả phí (%s R$)", "Plane crashed — skipped the paid revive (%s R$)"), tostring(d.Price or "?")))
                    end
                end)
            elseif kind == "Paused" then
                -- the server got our Buy and is processing it: never send a second one
                if d.FlightId == flight.id then flight.reviveBusy = true end
            elseif kind == "Revived" then
                flight.offerUntil, flight.reviveBusy = nil, nil
                F.reviveUsed = (F.reviveUsed or 0) + 1
            elseif kind == "Close" then
                if d.FlightId == nil or d.FlightId == flight.id then flight.offerUntil = nil end
                if typeof(d.Msg) == "string" then say("[revive] " .. d.Msg) end
            elseif kind == "Notice" and typeof(d.Msg) == "string" then
                say("[revive] " .. d.Msg)
            end
        end)
    end
    local function sessionFor(id)
        local ok, ups = pcall(debug.getupvalues, Smart.Update)
        if not ok then return nil end
        for _, v in pairs(ups) do if type(v) == "table" and v.Id == id and v.Home ~= nil then return v end end
    end
    local function lateral(sim, r)
        local pos = r.Pos + RingConfig.MotionOffset(r.Motion, r.Right, sim.Time or 0)
        return (pos - sim.Origin):Dot(sim.RightDirection or r.Right), pos.Y
    end
    -- ================= FLIGHT PLANNER v3: lane grid + dynamic programming =================
    -- Why v3: the game's HazardSystem.CheckSegment scans the WHOLE hazard list of the world on every
    -- call, and v2 called it tens of thousands of times per second (heavy lag → late Steer → crashes).
    --
    -- v3, every 0.12 s:
    --  1) ONE copy of the game's flight sim flies ~3.2 sim-s ahead with no steering: that gives the
    --     path centre line (where "lane 0, height 0" will be at each moment), the server clock for
    --     each moment, the ground below and the ceiling above.
    --  2) Only hazards whose X range overlaps that stretch are kept (sweep over the game's own list,
    --     which is sorted by X). Each one is placed at the SERVER clock of each moment
    --     (flightSimTime = (serverTime - StartTime) * 2.2), so lasers on/off, sweepers, swings,
    --     growers and leapers are where they will really be. Moving ones are also checked ±0.08 s.
    --  3) A grid of lanes (left/right × height) × time is marked blocked where an obstacle (plus the
    --     plane radius and a safety gap) would be. Tilted obstacles are tested exactly per cell.
    --  4) Dynamic programming finds the path that survives longest, then collects most rings / candy,
    --     keeps a gap from obstacles and changes lane as little as possible. Lane changes are limited
    --     to what the plane can really do (game's steering speeds and response, below 90 %).
    --  5) The steering input that reaches the next waypoint is solved exactly from the game's own
    --     steering formula (FlightSteering.Integrate), then sent with Steer.
    local Hz = Cfg.HazardSystem
    local FCfg = Cfg.FlightConfig or {}
    local TIME_SCALE = tonumber(FCfg.FlightTimeScale) or 2.2
    local STEER = FCfg.Steering or {}
    local VSTEER = FCfg.VerticalSteering or {}
    local LAT_SPEED = (tonumber(STEER.SteeringMaxSpeed) or 10) * (tonumber(STEER.SteeringSpeedMultiplier) or 1) -- studs per real second
    local LAT_K = tonumber(STEER.SteeringResponsiveness) or 11
    local V_SPEED = tonumber(VSTEER.VerticalSteeringSpeed) or 12
    local V_K = tonumber(VSTEER.VerticalSteeringResponse) or 8
    local V_DEAD = tonumber(VSTEER.Deadzone) or 0.12
    local H_MIN, H_MAX = tonumber(VSTEER.MinManualHeightOffset) or -12, tonumber(VSTEER.MaxManualHeightOffset) or 20
    local LAYER_DT, LAYERS = 0.16, 20                                     -- sim seconds per layer, ~3.2 sim-s
    local LAYER_REAL = LAYER_DT / TIME_SCALE
    local L_CELL = LAT_SPEED * LAYER_REAL * 0.85                          -- one lane per layer = 85 % of max side speed
    local H_CELL, H_EVERY = 2.0, 3                                        -- one height step per 3 layers ≈ 76 % of climb speed
    local PLANE_R = (Hz and tonumber(Hz.PlaneRadius)) or 1.1
    local HIT_R = PLANE_R + 1.3                                           -- + Steer latency / server drift margin
    local R_L, R_H = HIT_R + 0.45 * L_CELL + 0.3, HIT_R + 0.45 * H_CELL  -- blocked if any point of the cell is close (+0.3 side drift)
    local GEO = RingConfig and RingConfig.Geometry or {}
    local RING_HIT = (tonumber(GEO.HitRadius) or 5.7) - 0.9
    local SLOW_RING_RADIUS = (tonumber(GEO.HoleRadius) or 5) + 1.5
    local SURVIVE = 1000
    local plan = {flight = nil, nextAt = 0, cur = nil, seen = {}, ptr = 1, active = {}, world = nil}

    -- ---- Halloween candy pickups ("Candy" weather): the game's client keeps the live ones in
    -- workspace.CandyPickups_Local (one anchored part per pickup); the server collects them when the
    -- plane flies through. Radius from the weather config when the game exposes it.
    local AAW = RS:FindFirstChild("AdminAbuseWeather")
    local WeatherCfg
    pcall(function() WeatherCfg = require(AAW:WaitForChild("WeatherConfig", 5)) end)
    local CANDY_RADIUS = 6
    do
        local cc = WeatherCfg and type(WeatherCfg.Candy) == "table" and WeatherCfg.Candy
        local r = cc and tonumber(cc.CollectRadius or cc.PickupRadius or cc.CollectDistance or cc.Radius)
        if r and r > 0 then CANDY_RADIUS = r end
    end
    function F.candyActive()
        if not (WeatherCfg and WeatherCfg.IsActive) then return false end
        local ok, v = pcall(WeatherCfg.IsActive, "Candy")
        return ok and v == true
    end
    local candyEvt = AAW and AAW:FindFirstChild("CandyEvent")
    if candyEvt then
        on(candyEvt.OnClientEvent, function(kind, d)
            if kind == "Collected" and type(d) == "table" then
                S.stats.candy = (S.stats.candy or 0) + (tonumber(d.Value) or 0)
                flight.candyGot = (flight.candyGot or 0) + (tonumber(d.Value) or 0)
            end
        end)
    end

    -- server clock at flight sim time 0 (from Launched; measured once from the live sim otherwise)
    local function flightStart(sim)
        if flight.start then return flight.start end
        flight.start = workspace:GetServerTimeNow() - (sim.Time or 0) / TIME_SCALE
        return flight.start
    end

    -- What kind of obstacle is it, and what is it doing at that moment? (for the log)
    local function describe(hz, clock)
        if not hz then return tr("địa hình", "terrain") end
        local m = hz.Motion
        if hz.Laser then
            local st = Hz.LaserState and select(2, pcall(Hz.LaserState, hz, clock)) or "?"
            return "laser " .. tostring(st)
        elseif m and m.Kind == "Sweep" then return tr("vật lướt qua lại", "sweeping mover")
        elseif m and m.Kind == "Swing" then return tr("vật đung đưa", "swinging")
        elseif m and m.Kind == "Spin" then return tr("vật quay", "spinning")
        elseif m and m.Kind == "Grow" then return tr("vật phình to", "growing")
        elseif m and m.Kind == "Leap" then
            local st = Hz.LeapState and select(2, pcall(Hz.LeapState, m, clock)) or "?"
            return tr("vật bật nhảy ", "leaping ") .. tostring(st)
        end
        return tostring(hz.Kind or tr("vật cản", "obstacle")) .. tr(" đứng yên", " static")
    end

    -- ring value for the current mode
    local function ringValue(r)
        -- the laser-gate timing layer can force a ring (take / avoid) to change when we reach a gate
        local bias = plan.ringBias and plan.ringBias[r]
        if bias then return bias end
        if r.Type == "Slow" then return -25 end
        if S.gateMode then return (r.Type == "Speed" or r.Type == "Teleport") and 14 or 0 end
        if r.Type == "Speed" or r.Type == "Teleport" then return 13 end
        if r.Type == "Coins" or r.Type == "Break" then return 11 end
        return 8
    end

    -- hazards overlapping [x0, x1]: sweep over the game's list (sorted by MinX); amortised O(new hazards)
    local function hazardsAhead(world, x0, x1)
        local list = Hz.ByWorld and Hz.ByWorld[world]
        if not list then return {} end
        if plan.world ~= world or plan.ptrFlight ~= flight.id or x0 < (plan.lastX0 or -math.huge) - 50 then
            plan.world, plan.ptrFlight, plan.ptr, plan.active = world, flight.id, 1, {}
        end
        plan.lastX0 = x0
        while plan.ptr <= #list and list[plan.ptr].MinX <= x1 do
            local h = list[plan.ptr]
            if h.Collide ~= false and (h.MaxX or math.huge) >= x0 then plan.active[#plan.active + 1] = h end
            plan.ptr += 1
        end
        local keep = {}
        for _, h in ipairs(plan.active) do if (h.MaxX or math.huge) >= x0 then keep[#keep + 1] = h end end
        plan.active = keep
        return keep
    end

    local function ccell(v, lo, size) return math.floor((v - lo) / size + 0.5) end

    -- obstacle box at a server time. Lasers count from "warn" on (the beam is about to fire), not only "on".
    local function boxAt(h, t)
        if h.Laser and Hz.LaserState then
            local okS, st = pcall(Hz.LaserState, h, t)
            if not okS or st == "off" then return nil end
            local okB, cf, half = pcall(Hz.Box, h, t)
            if okB and cf then return cf, half end
            if h.Motion == nil then return (h.BoxCF or CFrame.new(h.Center)), h.Half end
            return nil
        end
        local okB, cf, half = pcall(Hz.Box, h, t)
        if okB then return cf, half end
        return nil
    end
    F.boxAt = boxAt

    -- ================= LASER-GATE TIMING =================
    -- Some lasers cover every lane from ground to ceiling (W3_S8_Laser_19, W3_S9_Laser_11: 52-54 wide,
    -- on 2.4 s / off 2.6 s). Steering cannot pass them; only WHEN the plane arrives matters, and forward
    -- speed does not depend on steering. The levers are the speed rings (RingConfig: Speed ×1.4 for 3 s
    -- ≈ 1.2 s earlier, Slow ×0.6 for 2.5 s ≈ 1 s later). Every 0.5 s: fly a copy of the sim ~25 sim-s ahead
    -- for "no speed ring" and for "take ring X" (each Speed/Slow ring before the gate), read the laser's
    -- on/off schedule at the arrival time, and steer the planner to take / avoid rings so the plane
    -- crosses while the laser is OFF (with a safety margin).
    local RINGS_CFG = RingConfig and RingConfig.Rings or {}
    local SPEED_FX = {Speed = RINGS_CFG.Speed or {Modifier = 1.4, Duration = 3}, Slow = RINGS_CFG.Slow or {Modifier = 0.6, Duration = 2.5}}
    local lasersOf = {}
    local function gateLasers(world)
        if lasersOf[world] then return lasersOf[world] end
        local out = {}
        for _, h in ipairs((Hz.ByWorld and Hz.ByWorld[world]) or {}) do if h.Laser and h.Collide ~= false then out[#out + 1] = h end end
        lasersOf[world] = out
        return out
    end
    -- does this laser block every lane the plane may use at its position?
    local function isGate(sim, h)
        local cf = h.BoxCF or CFrame.new(h.Center)
        local half = h.Half
        if not (cf and half) then return false end
        local Rdir = sim.RightDirection or Vector3.new(0, 0, 1)
        local Hd = sim.Heading or Vector3.new(1, 0, 0)
        local rel = cf.Position - (sim.Origin or Vector3.zero)
        local Lc = rel:Dot(Rdir)
        local rv, uv, kv = cf.RightVector, cf.UpVector, cf.LookVector
        local eR = math.abs(rv:Dot(Rdir)) * half.X + math.abs(uv:Dot(Rdir)) * half.Y + math.abs(kv:Dot(Rdir)) * half.Z
        local eU = math.abs(rv.Y) * half.X + math.abs(uv.Y) * half.Y + math.abs(kv.Y) * half.Z
        local okL, mn, mx = pcall(FlightSteering.Limits, sim.SteeringBounds, rel:Dot(Hd))
        if not (okL and mn and mx and mx > mn) then return false end
        -- height: the plane only has ~ground+4.5 … ceiling-1.5 to use; a laser 12+ studs tall covers that band
        return Lc - eR <= mn + 1.5 and Lc + eR >= mx - 1.5 and eU >= 6, rel:Dot(Hd), cf, half
    end
    -- fly a copy ahead; `fx` = list of {proj = along of a ring, kind = "Speed"/"Slow"} applied when passed.
    -- Returns function(proj) -> server clock when the plane reaches that along.
    local function arrivals(sim, start, fx, untilProj)
        local c = table.clone(sim)
        c.History, c.Replaying = nil, true
        c.ZoneNext = table.clone(sim.ZoneNext or {})
        c.SteeringInput, c.VerticalInput = 0, 0
        local Hd, O = sim.Heading or Vector3.new(1, 0, 0), sim.Origin or Vector3.zero
        local pts = {{(c.Pos - O):Dot(Hd), start + (c.Time or 0) / TIME_SCALE}}
        local used = {}
        for _ = 1, 260 do
            if not pcall(c._step, c, 0.1) then break end
            local p = (c.Pos - O):Dot(Hd)
            for i, e in ipairs(fx) do
                if not used[i] and p >= e.proj then
                    used[i] = true
                    local cfg = SPEED_FX[e.kind]
                    if cfg then pcall(c.SetSpeedEffect, c, cfg.Modifier, cfg.Duration, e.kind) end
                end
            end
            pts[#pts + 1] = {p, start + (c.Time or 0) / TIME_SCALE}
            if p > untilProj + 20 or c.Landed or c.Sliding or c.Impact then break end
        end
        return function(proj)
            for i = 1, #pts - 1 do
                local a, b = pts[i], pts[i + 1]
                if proj >= a[1] and proj <= b[1] then return a[2] + (b[2] - a[2]) * (proj - a[1]) / math.max(1e-6, b[1] - a[1]) end
            end
            return nil
        end
    end
    -- seconds of OFF time around the crossing window (negative = the laser is on/warn while crossing)
    local function gateMargin(h, tIn, tOut)
        if not (tIn and tOut and Hz.LaserState) then return -99 end
        local function off(t) local ok, st = pcall(Hz.LaserState, h, t) return ok and st == "off" end
        for t = tIn, tOut, 0.04 do if not off(t) then return -1 end end
        local m = 0
        while m < 1.2 and off(tIn - m - 0.04) and off(tOut + m + 0.04) do m += 0.04 end
        return m
    end
    local function timingPlan(sim, world, start)
        local Hd, O = sim.Heading or Vector3.new(1, 0, 0), sim.Origin or Vector3.zero
        local here = (sim.Pos - O):Dot(Hd)
        -- gates ahead (within ~1500 studs)
        local gates = {}
        for _, h in ipairs(gateLasers(world)) do
            local g, proj, _, half = isGate(sim, h)
            if g and proj > here + 5 and proj < here + 1500 then
                gates[#gates + 1] = {h = h, proj = proj, thick = (half and half.X or 0.6) + HIT_R}
            end
        end
        if #gates == 0 then plan.ringBias = nil return end
        table.sort(gates, function(a, b) return a.proj < b.proj end)
        local gate = gates[1]
        -- speed rings between us and the gate
        local rings = {}
        for _, r in pairs(flight.rings) do
            if (r.Type == "Speed" or r.Type == "Slow") and r.Pos then
                local p = (r.Pos - O):Dot(Hd)
                if p > here + 8 and p < gate.proj - 5 then rings[#rings + 1] = {r = r, proj = p, kind = r.Type} end
            end
        end
        local function score(fx)
            local at = arrivals(sim, start, fx, gate.proj + gate.thick)
            return gateMargin(gate.h, at(gate.proj - gate.thick), at(gate.proj + gate.thick)), at(gate.proj)
        end
        local base, baseAt = score({})
        local bias, choice, best = {}, nil, base
        for _, e in ipairs(rings) do
            local m = score({e})
            e.margin = m
            if m > best + 0.05 then best, choice = m, e end
        end
        local OK = 0.12                                  -- seconds of OFF time kept on both sides of the crossing
        if base >= OK then
            -- on time already: avoid the speed rings that would make us arrive while it is on
            for _, e in ipairs(rings) do if e.margin < OK then bias[e.r] = -300 end end
            choice = nil
        elseif choice and best >= OK then
            bias[choice.r] = 300
            for _, e in ipairs(rings) do if e ~= choice then bias[e.r] = -300 end end
        end
        plan.ringBias = next(bias) and bias or nil
        plan.gateOk = (base >= OK or (choice and best >= OK)) and gate.h.Id or nil
        -- log once per gate / decision
        local key = tostring(gate.h.Id) .. (choice and (":" .. tostring(choice.kind) .. tostring(math.floor(choice.proj))) or (base >= OK and ":ok" or ":none"))
        if plan.gateLog ~= key then
            plan.gateLog = key
            local inS = baseAt and (baseAt - workspace:GetServerTimeNow()) or 0
            if base >= OK then
                say(string.format(tr("Màn laser %s (%.0fs nữa): tới lúc laser TẮT (dư %.1fs)", "Laser gate %s (in %.0fs): arriving while it is OFF (%.1fs spare)"), tostring(gate.h.Id), inS, base))
            elseif choice and best >= OK then
                say(string.format(tr("Màn laser %s (%.0fs nữa) sẽ BẬT khi tới → lấy ring %s để đổi giờ tới (dư %.1fs)", "Laser gate %s (in %.0fs) would be ON → taking the %s ring to shift the arrival (%.1fs spare)"),
                    tostring(gate.h.Id), inS, tostring(choice.kind), best))
            else
                say(string.format(tr("Màn laser %s (%.0fs nữa) sẽ BẬT khi tới — chưa có ring Speed/Slow nào đổi được giờ (%d ring phía trước)", "Laser gate %s (in %.0fs) would be ON — no Speed/Slow ring ahead can fix the timing yet (%d rings)"),
                    tostring(gate.h.Id), inS, #rings))
            end
        end
    end

    local function planSteer(sim, axis, vaxis)
        if not (Hz and Hz.Box and Hz.SegmentBox and Hz.ByWorld) then return axis, vaxis end
        if sim.Impact then return axis, vaxis end
        if plan.flight ~= flight.id then
            plan.flight, plan.cur, plan.seen, plan.nextAt = flight.id, nil, {}, 0
            plan.ringBias, plan.gateLog, plan.timingAt = nil, nil, 0
        end
        local now0 = now()
        if now0 < plan.nextAt and plan.cur then return plan.cur[1], plan.cur[2] end
        plan.nextAt = now0 + 0.12
        local world, start = G.world(), flightStart(sim)
        if now0 >= (plan.timingAt or 0) then           -- laser-gate timing: twice a second is enough
            plan.timingAt = now0 + 0.5
            local okT, errT = pcall(timingPlan, sim, world, start)
            if not okT and now0 - (plan.timingErrAt or -99) > 30 then plan.timingErrAt = now0 say("[timing] " .. tostring(errT)) end
        end
        local Rdir = sim.RightDirection or Vector3.new(0, 0, 1)
        local UP = Vector3.new(0, 1, 0)

        -- 1) centre line ahead (one sim copy, no steering)
        local c = table.clone(sim)
        c.History, c.Replaying = nil, true
        c.ZoneNext = table.clone(sim.ZoneNext or {})
        c.SteeringInput, c.VerticalInput = 0, 0
        local base, simT, clock, along, hLo, hHi, lLo, lHi = {}, {}, {}, {}, {}, {}, {}, {}
        local K = 0
        for k = 0, LAYERS do
            if k > 0 then
                if not pcall(c._step, c, LAYER_DT / 2) then break end
                if not pcall(c._step, c, LAYER_DT / 2) then break end
                if c.Landed or c.Sliding then break end
            end
            local b = c.Pos - Rdir * (c.LateralOffset or 0) - UP * (c.ManualHeightOffset or 0)
            base[k], simT[k], clock[k], along[k] = b, c.Time or 0, start + (c.Time or 0) / TIME_SCALE, c.Along or 0
            -- height room, exactly as the game limits it (FlightSim._verticalStep):
            --   band = FlightSteering.VerticalBand(progress, ringLift)  (fades to 0 near the end of the map)
            --   ceiling = CeilingY (ground + MaxFlightAltitude 15) above the profile height → only ~7 studs of climb
            --   + ground / roof geometry from the sim's own ray casts
            local lo, hi = H_MIN, H_MAX
            local alongP = (c.World1 and c.PathAlong) or c.Along or 0
            local okP, py, prog, lift = pcall(c._profileY, c, alongP)
            if okP and py then
                local okB, bmin, bmax = pcall(FlightSteering.VerticalBand, prog, lift)
                if okB and bmin and bmax then lo, hi = math.max(lo, bmin), math.min(hi, bmax) end
                if c.CeilingY then hi = math.min(hi, c.CeilingY - py - 1.5) end    -- -1.5: climb slows in the last 3 studs
            end
            local okG, g = pcall(c._cast, c, b + UP * 2, UP * -70)
            if okG and g then lo = math.max(lo, g.Position.Y + 4.5 - b.Y) end
            local okC, ce = pcall(c._cast, c, b, UP * 60)
            if okC and ce then hi = math.min(hi, ce.Position.Y - 4.5 - b.Y) end
            if hi < lo then hi = lo end
            hLo[k], hHi[k] = lo, hi
            local okL, mn, mx = pcall(FlightSteering.Limits, sim.SteeringBounds, along[k])
            if okL and mn and mx and mx > mn then lLo[k], lHi[k] = mn, mx else lLo[k], lHi[k] = -40, 40 end
            K = k
            if c.Impact then break end
        end
        if K < 2 then return axis, vaxis end

        -- 2) grid around where the plane can be
        local L0, H0 = sim.LateralOffset or 0, sim.ManualHeightOffset or 0
        local VL, VH = sim.LateralVelocity or 0, sim.ManualHeightVelocity or 0
        -- network delay: the server keeps flying our PREVIOUS input until the new Steer arrives (~ping).
        -- Plan from where the plane will be when the new input starts to act, not from where it is now.
        local lat = 0.08
        pcall(function() lat = math.clamp((lp:GetNetworkPing() or 0) + 0.05, 0.03, 0.35) end)
        plan.lat = lat
        do
            local pa = plan.cur and plan.cur[1] or axis
            local pv = plan.cur and plan.cur[2] or vaxis
            local okI, nl, nvl = pcall(FlightSteering.Integrate, L0, VL, FlightSteering.Axis(pa) or 0, lat)
            if okI and nl then L0, VL = nl, nvl end
            local tv = (FlightSteering.VerticalAxis(pv) or 0) * V_SPEED
            local ev0 = math.exp(-V_K * lat)
            H0 = H0 + tv * lat + (VH - tv) * (1 - ev0) / V_K
            VH = tv + (VH - tv) * ev0
        end
        local reachL = LAT_SPEED * LAYER_REAL * K + 2
        local gl0 = math.max(-60, L0 - reachL)
        local NL = math.floor((math.min(60, L0 + reachL) - gl0) / L_CELL) + 1
        local gh0 = H_MIN
        local NH = math.floor((H_MAX - H_MIN) / H_CELL) + 1
        local function lv(li) return gl0 + li * L_CELL end
        local function hv(hi) return gh0 + hi * H_CELL end
        local function idx(li, hi) return li * NH + hi end

        -- valid cells per layer: inside the stage bounds, above ground / below ceiling, reachable in time
        local valid = {}
        for k = 0, K do
            local v = {}
            local tReal = (simT[k] - simT[0]) / TIME_SCALE
            local e = math.exp(-LAT_K * tReal)
            local A = (1 - e) / LAT_K
            local reachLo = L0 + VL * A - LAT_SPEED * (tReal - A) - 0.6 * L_CELL
            local reachHi = L0 + VL * A + LAT_SPEED * (tReal - A) + 0.6 * L_CELL
            local vReach = V_SPEED * tReal + math.abs(VH) * 0.2 + 0.6 * H_CELL
            for li = 0, NL - 1 do
                local L = lv(li)
                if L >= lLo[k] - 0.5 and L <= lHi[k] + 0.5 and L >= reachLo and L <= reachHi then
                    for hi = 0, NH - 1 do
                        local H = hv(hi)
                        -- half a cell of tolerance so a narrow height band still has a row of cells
                        if H >= hLo[k] - 0.5 * H_CELL and H <= hHi[k] + 0.5 * H_CELL and math.abs(H - H0) <= vReach then v[idx(li, hi)] = true end
                    end
                end
            end
            valid[k] = v
        end

        -- 3) obstacles → blocked cells (segment layer k → k+1)
        local blocked, hardB = {}, {}
        local x0, x1 = math.huge, -math.huge
        for k = 0, K do x0 = math.min(x0, base[k].X) x1 = math.max(x1, base[k].X) end
        local hz = hazardsAhead(world, x0 - 6, x1 + 6)
        -- nothing ahead to dodge or collect: the game's auto-pilot flies (cheapest)
        local anyRing = false
        for _, r in pairs(flight.rings) do if r.Pos and ringValue(r) ~= 0 then anyRing = true break end end
        local candyFolder = workspace:FindFirstChild("CandyPickups_Local")
        if #hz == 0 and not anyRing and not (candyFolder and #candyFolder:GetChildren() > 0) then
            plan.cur = {axis, vaxis}
            return axis, vaxis
        end
        local shieldEnds = flight.shieldEnds
        for k = 0, K - 1 do
            local bl, hard = {}, {}
            blocked[k], hardB[k] = bl, hard
            if not (shieldEnds and clock[k + 1] < shieldEnds - 0.15) then
                local b0, b1 = base[k], base[k + 1]
                local xa, xb = math.min(b0.X, b1.X), math.max(b0.X, b1.X)
                for _, h in ipairs(hz) do
                    if (h.MaxX or math.huge) >= xa - HIT_R and (h.MinX or -math.huge) <= xb + HIT_R then
                        local dyn = h.Motion ~= nil or h.Laser ~= nil
                        local clk = (clock[k] + clock[k + 1]) / 2
                        -- lasers: ±0.5 s window → go around a partial laser instead of betting on its on/off timing
                        -- (a full-width gate the timing layer has already timed: ±0.1 s, its margin is checked there)
                        local slacks = h.Laser and (plan.gateOk == h.Id and {0, 0.1, -0.1} or {0, 0.25, -0.25, 0.5, -0.5})
                            or (dyn and {0, 0.12, -0.12}) or {0}
                        for _, sl in ipairs(slacks) do
                            local cf, half = boxAt(h, clk + sl)
                            if cf and half then
                                local rv, uv, kv = cf.RightVector, cf.UpVector, cf.LookVector
                                local hx, hy, hzz = half.X, half.Y, half.Z
                                local ex = math.abs(rv.X) * hx + math.abs(uv.X) * hy + math.abs(kv.X) * hzz
                                local p = cf.Position
                                if p.X + ex + HIT_R >= xa and p.X - ex - HIT_R <= xb then
                                    local f = (b1.X ~= b0.X) and math.clamp((p.X - b0.X) / (b1.X - b0.X), 0, 1) or 0
                                    local bb = b0:Lerp(b1, f)
                                    local rel = p - bb
                                    local Lc, Hc = rel:Dot(Rdir), rel.Y
                                    local eR = math.abs(rv:Dot(Rdir)) * hx + math.abs(uv:Dot(Rdir)) * hy + math.abs(kv:Dot(Rdir)) * hzz
                                    local eU = math.abs(rv.Y) * hx + math.abs(uv.Y) * hy + math.abs(kv.Y) * hzz
                                    -- box axes lined up with the lanes? then the projection is exact
                                    local aligned = true
                                    for _, ax in ipairs({rv, uv, kv}) do
                                        local m = math.max(math.abs(ax:Dot(Rdir)), math.abs(ax.Y), math.abs(ax:Dot(sim.Heading or Vector3.new(1, 0, 0))))
                                        if m < 0.97 then aligned = false break end
                                    end
                                    local liA = math.max(0, math.ceil((Lc - eR - R_L - gl0) / L_CELL))
                                    local liB = math.min(NL - 1, math.floor((Lc + eR + R_L - gl0) / L_CELL))
                                    local hiA = math.max(0, math.ceil((Hc - eU - R_H - gh0) / H_CELL))
                                    local hiB = math.min(NH - 1, math.floor((Hc + eU + R_H - gh0) / H_CELL))
                                    -- hard = the plane itself would touch it (crash); soft = inside the safety gap
                                    local HARD = PLANE_R + 0.35
                                    for li = liA, liB do
                                        for hi = hiA, hiB do
                                            local id = idx(li, hi)
                                            if not hard[id] then
                                                local isHard, isSoft
                                                if aligned then
                                                    isSoft = true
                                                    isHard = math.abs(lv(li) - Lc) <= eR + HARD and math.abs(hv(hi) - Hc) <= eU + HARD
                                                else
                                                    local off = Rdir * lv(li) + UP * hv(hi)
                                                    local okS, s = pcall(Hz.SegmentBox, cf, half, b0 + off, b1 + off, HIT_R + 0.45 * L_CELL)
                                                    isSoft = okS and s ~= nil
                                                    if isSoft then
                                                        local okH, s2 = pcall(Hz.SegmentBox, cf, half, b0 + off, b1 + off, HARD)
                                                        isHard = okH and s2 ~= nil
                                                    end
                                                end
                                                if isHard then hard[id] = h bl[id] = h elseif isSoft then bl[id] = h end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 4) rewards: rings / candy flown through, gap from obstacles
        local reward = {}
        for k = 0, K - 1 do reward[k] = {} end
        local function addTarget(pos, rad, value, k)
            local b0, b1 = base[k], base[k + 1]
            local f = (b1.X ~= b0.X) and math.clamp((pos.X - b0.X) / (b1.X - b0.X), 0, 1) or 0
            local rel = pos - b0:Lerp(b1, f)
            local Lr, Hr = rel:Dot(Rdir), rel.Y
            local rw = reward[k]
            for li = math.max(0, math.ceil((Lr - rad - gl0) / L_CELL)), math.min(NL - 1, math.floor((Lr + rad - gl0) / L_CELL)) do
                for hi = math.max(0, math.ceil((Hr - rad - gh0) / H_CELL)), math.min(NH - 1, math.floor((Hr + rad - gh0) / H_CELL)) do
                    local dl, dh = lv(li) - Lr, hv(hi) - Hr
                    if dl * dl + dh * dh <= rad * rad then
                        local id = idx(li, hi)
                        rw[id] = (rw[id] or 0) + value
                    end
                end
            end
        end
        local function layerOfX(x)
            for k = 0, K - 1 do
                local xa, xb = math.min(base[k].X, base[k + 1].X), math.max(base[k].X, base[k + 1].X)
                if x >= xa and x <= xb then return k end
            end
        end
        for _, r in pairs(flight.rings) do
            local val = r.Pos and ringValue(r) or 0
            if val ~= 0 then
                local okP, off = pcall(RingConfig.MotionOffset, r.Motion, r.Right, simT[0])
                local p0 = r.Pos + (okP and off or Vector3.zero)
                local k = layerOfX(p0.X)
                if k then
                    local okQ, off2 = pcall(RingConfig.MotionOffset, r.Motion, r.Right, simT[k])
                    addTarget(r.Pos + (okQ and off2 or Vector3.zero), (val < 0 and r.Type == "Slow") and SLOW_RING_RADIUS or RING_HIT, val * (1 - 0.06 * k), k)
                end
            end
        end
        local candyW = S.on.candy and 40 or (S.gateMode and 0 or 6)
        if candyW > 0 then
            local folder = workspace:FindFirstChild("CandyPickups_Local")
            if folder then
                for _, p in ipairs(folder:GetChildren()) do
                    if p:IsA("BasePart") then
                        local k = layerOfX(p.Position.X)
                        if k then addTarget(p.Position, CANDY_RADIUS - 0.5, candyW * (1 - 0.06 * k), k) end
                    end
                end
            end
        end

        -- 5) dynamic programming (back to front): survive longest, then rewards, gap, smoothness
        local value, nextOf = {}, {}
        value[K] = {}
        for id in pairs(valid[K]) do value[K][id] = 0 end
        for k = K - 1, 0, -1 do
            local vk, nk, vn = {}, {}, value[k + 1]
            local bl, hb, rw, vd = blocked[k], hardB[k], reward[k], valid[k]
            local canClimb = (k % H_EVERY) == 0
            for id in pairs(vd) do
                if hb[id] then
                    vk[id] = 0                                        -- crash here: survival ends
                else
                    local li, hi = id // NH, id % NH
                    -- gap from obstacles: neighbours blocked in this layer cost a little
                    local near = 0
                    if (li > 0 and bl[idx(li - 1, hi)]) or (li < NL - 1 and bl[idx(li + 1, hi)]) then near += 4 end
                    if (hi > 0 and bl[idx(li, hi - 1)]) or (hi < NH - 1 and bl[idx(li, hi + 1)]) then near += 4 end
                    -- an obstacle coming up in this lane soon: leave it early, not at the last moment
                    for d = 1, 3 do
                        local bf = blocked[k + d]
                        if bf and bf[id] then near += 6 / d break end
                    end
                    local late = 1 + 0.12 * k                       -- the same lane change costs more the later it is
                    local best, bestId = -math.huge, nil
                    for dl = -1, 1 do
                        for dh = (canClimb and -1 or 0), (canClimb and 1 or 0) do
                            local nl, nh = li + dl, hi + dh
                            local nid = idx(nl, nh)
                            local nv = (nl >= 0 and nl < NL and nh >= 0 and nh < NH) and vn[nid] or nil
                            if nv then
                                nv = nv - (math.abs(dl) * 0.6 + math.abs(dh) * 1.0) * late
                                if nv > best then best, bestId = nv, nid end
                            end
                        end
                    end
                    if not bestId then best = 0 end
                    -- inside the safety gap only: survives, but costs a lot (used only when nothing is fully clear)
                    local gapCost = bl[id] and 400 or 0
                    vk[id] = SURVIVE - gapCost + (rw[id] or 0) - near - 0.05 * math.abs(hv(hi)) + best
                    nk[id] = bestId
                end
            end
            value[k], nextOf[k] = vk, nk
        end

        -- start cell = where the plane is now (nearest valid cell)
        local sl, sh = math.clamp(ccell(L0, gl0, L_CELL), 0, NL - 1), math.clamp(ccell(H0, gh0, H_CELL), 0, NH - 1)
        local startId = idx(sl, sh)
        if not value[0][startId] then
            local bestD
            for id in pairs(value[0]) do
                local d = math.abs(id // NH - sl) + math.abs(id % NH - sh)
                if not bestD or d < bestD then bestD, startId = d, id end
            end
        end
        if not value[0][startId] then return axis, vaxis end
        -- follow the best path
        local path, id, alive = {[0] = startId}, startId, 0
        for k = 0, K - 1 do
            if hardB[k][id] then break end
            alive = k + 1
            id = nextOf[k] and nextOf[k][id]
            if not id then break end
            path[k + 1] = id
        end

        -- 6) steering that reaches the waypoint ~2 layers ahead (exact inverse of the game's formulas)
        -- the waypoint at least (delay + 0.1 s) ahead; the new input only acts after the network delay
        -- Smooth tracking (no bang-bang): aim at the waypoint ≥ (delay + 0.25 s) ahead and ask for the
        -- AVERAGE side speed needed to get there. Side speed follows the input within ~0.09 s, so the
        -- command fades to 0 as the plane reaches its lane: no overshoot even with a late server.
        -- Tracking controller = the path's own side speed (feed-forward) + a gentle correction of the
        -- position error, both taken at the moment the new input starts to act (now + network delay).
        local function pathAt(tReal)                     -- planned lane / height and their speeds at now + tReal
            local ts = simT[0] + tReal * TIME_SCALE
            local k = 0
            while k < #path - 1 and simT[k + 1] and simT[k + 1] <= ts do k += 1 end
            local p0, p1 = path[k], path[k + 1] or path[k]
            local t0, t1 = simT[k], simT[k + 1] or (simT[k] + LAYER_DT)
            local f = math.clamp((ts - t0) / math.max(1e-6, t1 - t0), 0, 1)
            local la, lb = lv(p0 // NH), lv(p1 // NH)
            local ha, hb = hv(p0 % NH), hv(p1 % NH)
            local dtr = math.max(1e-3, (t1 - t0) / TIME_SCALE)
            return la + (lb - la) * f, (lb - la) / dtr, ha + (hb - ha) * f, (hb - ha) / dtr
        end
        local Lp, vLp = pathAt(lat)
        local Lahead = pathAt(lat + 0.12)               -- small look-ahead keeps it ahead of the lane change
        local a = math.clamp((vLp + ((Lp + Lahead) / 2 - L0) / 0.15) / LAT_SPEED, -1, 1)
        if math.abs(a) < (tonumber(STEER.SteeringDeadzone) or 0.08) then a = 0 end
        local T = 0.15
        -- height: look further (height changes are slow) — first height step on the path
        local Hgoal = Ht
        do   -- height changes are slow: aim at the height planned ~1 sim-s ahead
            local jv = math.min(6, #path)
            if path[jv] then Hgoal = hv(path[jv] % NH) T = math.max(0.15, (simT[jv] - simT[0]) / TIME_SCALE - lat) end
        end
        local v = math.clamp((Hgoal - H0) / T / V_SPEED, -1, 1)
        if math.abs(v) < V_DEAD then v = (math.abs(Hgoal - H0) > 1.2) and (v > 0 and V_DEAD or -V_DEAD) or 0 end
        plan.cur = {a, v}
        -- remember the planned positions (server clock → world position) for the crash report
        do
            local pts = {}
            for k = 0, K do
                local pid = path[k]
                if not pid then break end
                pts[#pts + 1] = {clock[k], base[k] + Rdir * lv(pid // NH) + UP * hv(pid % NH)}
            end
            plan.trace, plan.lastHz = pts, hz
            -- keep the last ~2 s of plans: the crash event arrives a ping late, after newer plans
            plan.traces = plan.traces or {}
            table.insert(plan.traces, pts)
            if #plan.traces > 16 then table.remove(plan.traces, 1) end
        end

        -- log: what forced a lane change (first obstacle on the straight lane), and dead ends
        local straight = idx(sl, sh)
        -- a laser covering every reachable lane at that moment = a timing gate: steering cannot pass it
        if alive < K then
            local hk = hardB[alive]
            local gate
            for id in pairs(valid[alive] or {}) do
                local h = hk and hk[id]
                if not (h and h.Laser) then gate = nil break end
                gate = h
            end
            if gate and plan.gateOk ~= gate.Id and not plan.seen["gate:" .. tostring(gate.Id)] then
                plan.seen["gate:" .. tostring(gate.Id)] = true
                say(string.format(tr("Màn laser %s phủ kín mọi làn và sẽ BẬT khi máy bay tới (%.1fs) — lái không né được, chỉ canh giờ",
                    "Laser gate %s covers every lane and will be ON when the plane arrives (%.1fs) — steering cannot pass it, timing only"),
                    tostring(gate.Id), simT[alive] - simT[0]))
            end
        end
        for k = 0, K - 1 do
            local h = blocked[k][straight]
            if h then
                local hid = tostring(h.Id)
                if not plan.seen[hid] then
                    plan.seen[hid] = true
                    flight.dodges = (flight.dodges or 0) + 1
                    say(string.format(tr("Né %s [%s] (%.1fs tới) · lái %+.2f / %+.2f%s", "Dodge %s [%s] (in %.1fs) · steer %+.2f / %+.2f%s"),
                        hid, describe(h, clock[k]), simT[k] - simT[0], a, v,
                        alive < K and string.format(tr(" · KHÔNG có đường an toàn (còn %.1fs)", " · NO safe path (%.1fs left)"), simT[alive] - simT[0]) or ""))
                end
                break
            end
        end
        return a, v
    end

    local lastSend, lastA, lastV = 0, nil, nil
    on(Run.Heartbeat, function(dt)
        if flight.state ~= "FLYING" or not flight.id or not Smart then steering = false return end
        if not (flights and flights[flight.id]) then
            flights = nil
            for _, v in ipairs(candidates) do local x = rawget(v, flight.id) if type(x) == "table" and x.Sim then flights = v break end end
            if not flights then return end
        end
        local fl = flights[flight.id]
        local sim = fl and fl.Sim
        if not sim or sim.Landed then return end
        steering = true
        flight.sim = sim
        local s = sessionFor(flight.id)
        if s then
            s.Home = 0
            -- keep the auto dodge on for the whole flight (the session caches its stage-5 cut-off)
            s.EndAlong = false
            if s.Expired then s.Expired = nil end
        end
        pcall(Smart.Update, fl, dt)
        local axis = FlightSteering.Axis(assistL) or 0
        local vaxis = FlightSteering.VerticalAxis(assistV) or 0
        do
            local okP, pa, pv = pcall(planSteer, sim, axis, vaxis)
            if okP then axis, vaxis = pa, pv elseif now() - (plan.errAt or -99) > 30 then plan.errAt = now() say("[planner] " .. tostring(pa)) end
        end
        F.cmd = {axis, vaxis}          -- the game's own steering loop now sends exactly this too
        pcall(function() sim:SetSteering(axis) sim:SetVerticalSteering(vaxis) end)
        local t = now()
        -- backup sender only (the game sends ~10/s; the server accepts 20/s in total)
        if t - lastSend >= 0.25 or ((axis ~= lastA or vaxis ~= lastV) and t - lastSend >= 0.12) then
            PlaneFlight.FireServer(PlaneFlight, "Steer", flight.id, axis, vaxis)
            lastSend, lastA, lastV = t, axis, vaxis
        end
    end)
    -- crash report: what the planner knew, and how far the client sim was from the server's plane
    on(PlaneFlight.OnClientEvent, function(kind, d)
        if type(d) ~= "table" or d.FlightId ~= flight.id then return end
        if kind == "SteeringState" then
            flight.srv = {off = tonumber(d.Offset), voff = tonumber(d.VOffset), along = tonumber(d.Along), t = tonumber(d.Time)}
            -- tracking quality: the server's real side position vs the planned one at the same moment
            pcall(function()
                local sim, off, st = flight.sim, tonumber(d.Offset), tonumber(d.Time)
                if not (sim and off and st and flight.start and plan.traces) then return end
                local clk = flight.start + st / TIME_SCALE
                local Rd, O = sim.RightDirection or Vector3.new(0, 0, 1), sim.Origin or Vector3.zero
                for ti = #plan.traces, 1, -1 do
                    local tr_ = plan.traces[ti]
                    if tr_[1] and tr_[1][1] <= clk then
                        for i = 1, #tr_ - 1 do
                            local p, q = tr_[i], tr_[i + 1]
                            if clk >= p[1] and clk <= q[1] then
                                local pos = p[2]:Lerp(q[2], (clk - p[1]) / math.max(1e-6, q[1] - p[1]))
                                local err = math.abs(off - (pos - O):Dot(Rd))
                                local tk = plan.track or {n = 0, sum = 0, max = 0, at = now()}
                                plan.track = tk
                                tk.n += 1 tk.sum += err tk.max = math.max(tk.max, err)
                                if now() - tk.at >= 5 and tk.n > 0 then
                                    say(string.format(tr("[bám đường] lệch ngang so với kế hoạch: TB %.2f · lớn nhất %.2f studs (%d mẫu, ping %.0f ms)",
                                        "[tracking] side error vs plan: avg %.2f · max %.2f studs (%d samples, ping %.0f ms)"),
                                        tk.sum / tk.n, tk.max, tk.n, (plan.lat or 0) * 1000))
                                    plan.track = {n = 0, sum = 0, max = 0, at = now()}
                                end
                                return
                            end
                        end
                    end
                end
            end)
        elseif kind == "HazardCrash" then
            local sim, srv = flight.sim, flight.srv
            local predicted = plan.seen[tostring(d.HazardId)] and tr("đã thấy trước", "seen before") or tr("KHÔNG thấy trước", "NOT seen before")
            local drift = (sim and srv and srv.off) and string.format(" · lệch ngang %.1f", (sim.LateralOffset or 0) - srv.off) or ""
            if sim then
                local hgt = sim.ManualHeightOffset or 0
                local room = sim.CeilingY and sim.Pos and (sim.CeilingY - sim.Pos.Y) or nil
                drift = drift .. string.format(" · L %.1f H %.1f%s", sim.LateralOffset or 0, hgt, room and string.format(" (trần còn %.1f)", room) or "")
            end
            say(string.format(tr("[va chạm] %s (%s) · %s%s · lái cuối %+.1f/%+.0f", "[crash] %s (%s) · %s%s · last steer %+.1f/%+.0f"),
                tostring(d.HazardId), tostring(d.Kind or d.Type), predicted, drift, tonumber(lastA) or 0, tonumber(lastV) or 0))
            -- diagnosis: was the planned position safe by our model, and how far was the plane from it?
            --   box→crash  ≈ 0 and box→planned big  → the plane did not follow the plan (control / drift)
            --   box→planned small too                 → the plan itself was wrong (model: timing, size, ceiling…)
            --   box→crash big                         → our obstacle model differs from the server's
            pcall(function()
                local hzId = tostring(d.HazardId)
                local h, inPlan
                for _, x in ipairs(plan.lastHz or {}) do if tostring(x.Id) == hzId then h, inPlan = x, true break end end
                if not h then
                    for _, x in ipairs((Hz and Hz.ByWorld and Hz.ByWorld[G.world()]) or {}) do if tostring(x.Id) == hzId then h = x break end end
                end
                if not h then say("[crash-diag] " .. hzId .. " is not in the game's hazard list") return end
                local t = tonumber(d.ServerTime) or workspace:GetServerTimeNow()
                local cf, half = boxAt(h, t)
                local function dist(p)
                    if not (cf and half and typeof(p) == "Vector3") then return nil end
                    local q = cf:PointToObjectSpace(p)
                    local dx = math.max(0, math.abs(q.X) - half.X)
                    local dy = math.max(0, math.abs(q.Y) - half.Y)
                    local dz = math.max(0, math.abs(q.Z) - half.Z)
                    return math.sqrt(dx * dx + dy * dy + dz * dz)
                end
                local planned
                -- newest plan that already covered the crash moment
                for ti = #(plan.traces or {}), 1, -1 do
                    local tr_ = plan.traces[ti]
                    if tr_[1] and tr_[1][1] <= t then
                        for i = 1, #tr_ - 1 do
                            local a, b = tr_[i], tr_[i + 1]
                            if t >= a[1] and t <= b[1] then planned = a[2]:Lerp(b[2], (t - a[1]) / math.max(1e-6, b[1] - a[1])) break end
                        end
                        if planned then break end
                    end
                end
                local actual = typeof(d.Pos) == "Vector3" and d.Pos or nil
                local function f(x) return x and string.format("%.1f", x) or "?" end
                local st = (h.Laser and Hz.LaserState) and select(2, pcall(Hz.LaserState, h, t)) or "-"
                say(string.format("[crash-diag] %s inPlan=%s motion=%s laser=%s · box→crash %s · box→planned %s · planned↔crash %s · size %s",
                    hzId, tostring(inPlan == true), h.Motion and tostring(h.Motion.Kind) or "none", tostring(st),
                    f(dist(actual)), f(dist(planned)), (planned and actual) and f((planned - actual).Magnitude) or "?",
                    half and string.format("%.0fx%.0fx%.0f", half.X * 2, half.Y * 2, half.Z * 2) or "?"))
            end)
        end
    end)
    local function launchRegion()
        local gp = G.gameplay()
        local z = gp and gp:FindFirstChild("PlaneLaunchZone")
        return z and z:FindFirstChild("LaunchRegion")
    end
    local function begin(id)
        local a = {sent = now()}
        attempt[id] = a
        PlaneFlight.FireServer(PlaneFlight, "ChargeBegin", id)
        while S.alive and not a.accepted and not a.result and now() - a.sent < 2 do task.wait() end
        return a, id
    end
    function F.throwOnce(token)
        flight.state = "IDLE"
        local r = launchRegion()
        local _, rootPart = G.char()
        if not (r and rootPart) then say("Không thấy vùng phóng — đợi tải map") return false end
        local o = r.CFrame:PointToObjectSpace(rootPart.Position)
        if math.abs(o.X) > r.Size.X / 2 - 2 or math.abs(o.Z) > r.Size.Z / 2 - 2 or math.abs(o.Y) > r.Size.Y / 2 + 4 then
            G.tp(r.CFrame + Vector3.new(0, 3, 0))
        end
        G.equipTool()
        local a, id = begin(S.attemptNext + 1)
        if a.result == "REJECTED" and typeof(a.next) == "number" then a, id = begin(a.next) end
        S.attemptNext = id
        if not a.accepted then say(tr("Ném bị từ chối: ", "Throw refused: ") .. tostring(a.msg or a.result or "timeout")) return false end
        while S.alive and now() - a.sent < 0.7557 do task.wait() end
        PlaneFlight.FireServer(PlaneFlight, "ChargeRelease", id, now() - a.sent)
        local t = now()
        while S.alive and a.result ~= "THROWN" and now() - t < 3 do task.wait() end
        if a.result ~= "THROWN" then say("Lượt ném không được chấp nhận") return false end
        S.stats.throws += 1
        say(string.format(tr("SUPER THROW · lực %.0f%% · tier %s", "SUPER THROW · power %.0f%% · tier %s"),(tonumber(a.power) or 0) * 100, tostring(a.tier)))
        F.patch(true)
        flight.throwAt = now()
        return true            -- non-blocking: steering runs on Heartbeat, the character is free for other tasks
    end
    -- true when no flight of ours is in the air (with a watchdog for lost events)
    function F.idle()
        local st = flight.state
        -- a revive offer for our crashed plane is open: the run may continue, don't throw a new plane yet
        if flight.offerUntil and now() < flight.offerUntil and st ~= "FLYING" then return false end
        if st == "IDLE" or st == "RETURNED" then return true end
        if st == "THROWN" and flight.throwAt and now() - flight.throwAt > 25 then
            say(tr("Máy bay không cất cánh sau 25 giây — ném lại", "Plane did not launch in 25 s — throwing again"))
            flight.state, steering = "IDLE", false
            return true
        end
        if flight.throwAt and now() - flight.throwAt > 360 then
            say("Mất tín hiệu chuyến bay — đặt lại")
            flight.state, steering = "IDLE", false
            return true
        end
        return false
    end
    function F.status()
        if F.idle() then return nil end
        return string.format(tr("Đang bay · %ds · %d ring · %d va chạm", "Flying · %ds · %d rings · %d crashes"),math.floor(now() - (flight.throwAt or now())), flight.got, flight.hazards)
    end
    F.restore = function() steering = false F.patch(false) end
end

-- ============================================================ TRAINING
local T = {}
local U = {}          -- declared early: the training loop calls U.unlockAction()
-- right-side notification cards (filled in by the GUI section): N.push{kind, title, status, lines, color, ok}
local N = {}
local function notify(spec) if N.push then pcall(N.push, spec) end end
-- plane facts for notifications, from the game's own PlaneConfig
local function planeFacts(id)
    local PC = Cfg.PlaneConfig
    local c = PC and ((PC.Get and PC.Get(id)) or (PC.Planes and PC.Planes[id]))
    if not c then return {name = tostring(id), rarity = "?"} end
    return {name = c.DisplayName or tostring(id), rarity = tostring(c.Rarity or "?"),
        power = tonumber(c.BasePlanePower) or 0, base = tonumber(c.BasePower) or 0,
        speed = tonumber(c.ProgressionSpeed or c.LaunchPowerMultiplier) or 1,
        coins = tonumber(c.MoneyMultiplier or c.CoinsMultiplier) or 1, map = c.MapId}
end
do
    local TC = Cfg.TrainingConfig
    on(TrainingRE.OnClientEvent, function(kind, d)
        if type(d) ~= "table" then return end
        -- the game's own client may own the training request (auto-start in zone), so claim with the offer's Request
        if kind == "BonusOffer" and typeof(d.Id) == "string" and (S.on.unlock or S.on.farm) then
            task.delay(0.15 + math.random() * 0.2, function()
                TrainingRE.FireServer(TrainingRE, "ClaimBonus", d.Request, d.Id)
                say(tr("Nhận x", "Claimed x") .. tostring(d.Multiplier or 2) .. " POWER")
            end)
        elseif kind == "BonusResult" then
            if d.Ok ~= true then say("x2 POWER bị từ chối") end
        end
    end)
    function T.bestZone()
        if not TC then return nil end
        local reb = 0
        local ls = lp:FindFirstChild("leaderstats")
        if ls and ls:FindFirstChild("Rebirths") then reb = ls.Rebirths.Value end
        local best, chosen
        -- zone picked on the task that is driving the training (Auto Farm & Rebirth or Auto Unlock World)
        local pick = (S.on.farm and not S.on.unlock) and S.opt.farm or S.opt.unlock
        for _, z in ipairs(TC.ZonesForWorld(G.world())) do
            local ok = TC.IsUnlocked(z.Id, reb, function(k) return lp:GetAttribute("Pass_" .. tostring(k)) == true end)
            if ok and (not best or z.Tier > best.Tier) then best = z end
            if ok and tonumber(pick) == z.Id then chosen = z end
        end
        return chosen or best
    end
    function T.zoneOptions()
        local out = {{id = "auto", label = tr("Tự động · ô tốt nhất đã mở", "Auto · best unlocked zone")}}
        if not TC then return out end
        local ls = lp:FindFirstChild("leaderstats")
        local reb = ls and ls:FindFirstChild("Rebirths") and ls.Rebirths.Value or 0
        for _, z in ipairs(TC.ZonesForWorld(G.world())) do
            local ok = TC.IsUnlocked(z.Id, reb, function(k) return lp:GetAttribute("Pass_" .. tostring(k)) == true end)
            out[#out + 1] = {id = z.Id, label = string.format("%s · tier %d%s", tostring(z.Name), z.Tier, ok and "" or tr(" (khoá)", " (locked)")), disabled = not ok}
        end
        return out
    end
    function T.session(token, seconds)
        local z = T.bestZone()
        if not z then say("Chưa tìm được ô tập") return false end
        local model = TC.Model(z.Id)
        local point = model and (model:FindFirstChild("TrainingPoint") or model:FindFirstChild("Region"))
        if not point then
            local gp = G.gameplay()
            local spawn = gp and gp:FindFirstChild("ProgressionSpawn")
            if spawn then G.tp(spawn.CFrame + Vector3.new(0, 4, 0), 1) end
            model = TC.Model(z.Id)
            point = model and (model:FindFirstChild("TrainingPoint") or model:FindFirstChild("Region"))
            if not point then say("Ô tập " .. z.Name .. " chưa tải xong") return false end
        end
        G.tp(point.CFrame + Vector3.new(0, 3, 0), 0.6)
        local t = now()
        while G.alive(token) and lp:GetAttribute("TrainingZone") ~= z.Id and now() - t < 3 do task.wait(0.1) end
        S.trainSeq += 1
        local seq = S.trainSeq
        TrainingRE.FireServer(TrainingRE, "Start", seq)
        say(tr("Luyện lực · ", "Training · ") .. tostring(z.Name) .. " (tier " .. z.Tier .. ")")
        local p0 = tonumber(lp:GetAttribute("TrainingPower")) or 0
        t = now()
        local restarts = 0
        while G.alive(token) and now() - t < seconds do
            if not (S.on.unlock or S.on.farm) then break end
            if (S.on.throw or S.on.candy) and F.idle() and now() - t > seconds and seconds > 60 then break end
            -- higher-priority work became possible: hand the character back to the scheduler right away
            -- 100% reached (rebirth available) or a new world opened: hand control back to the unlock planner
            local ready
            if S.on.unlock then ready = U.unlockAction()
            else ready = lp:GetAttribute("CanRebirth") == true and lp:GetAttribute("RebirthCapped") ~= true end
            if F.idle() and now() - t > 3 and ready then say(tr("Đủ điều kiện bước tiếp — dừng luyện", "Ready for the next step — stopping training")) break end
            if (tonumber(lp:GetAttribute("HighestUnlockedWorld")) or 1) > G.world() and F.idle() then break end
            if now() - t > 4 and lp:GetAttribute("IsTraining") ~= true and lp:GetAttribute("TrainingClientState") ~= "TRAINING" then
                if not F.idle() and restarts >= 1 then
                    -- server won't let us train while our plane flies: wait for it instead
                    T.blockUntil = now() + 300
                    say("Không luyện được khi máy bay đang bay — chờ máy bay về")
                    break
                end
                restarts += 1
                S.trainSeq += 1 seq = S.trainSeq
                TrainingRE.FireServer(TrainingRE, "Start", seq)
                task.wait(1)
            end
            task.wait(0.2)
        end
        S.trainSeq += 1
        TrainingRE.FireServer(TrainingRE, "Exit", S.trainSeq)
        local gained = (tonumber(lp:GetAttribute("TrainingPower")) or 0) - p0
        say(string.format(tr("Luyện xong +%s Power", "Training done +%s Power"), tostring(math.floor(gained))))
        task.wait(0.5)
        return true
    end
end

-- ============================================================ UPGRADE: rebirth, world, shops, fold, fuse
do
    U.next = {}            -- per-task cooldown clocks
    local function due(k, gap) if (U.next[k] or 0) > now() then return false end U.next[k] = now() + gap return true end
    U.due = due
    function U.rebirth()
        if lp:GetAttribute("CanRebirth") ~= true then return false end
        local r = G.call("Rebirth")
        say(r.ok and tr("REBIRTH thành công", "REBIRTH done") or (tr("Rebirth lỗi: ", "Rebirth failed: ") .. tostring(r.msg)))
        task.wait(1)
        return r.ok
    end
    -- next-world gate requirement (WorldGateConfig): enough rebirths to open every normal training zone, then reach the finish gate
    function U.gateReq()
        local w = G.world()
        local ls = lp:FindFirstChild("leaderstats")
        local reb = ls and ls:FindFirstChild("Rebirths") and ls.Rebirths.Value or 0
        local WG = Cfg.WorldGateConfig
        -- per-world task: rebirths of the highest NON-premium training zone of this world (WorldGateConfig.Requirement rule)
        local need, zoneName = 0, nil
        local TC = Cfg.TrainingConfig
        if TC and TC.ZonesForWorld then
            for _, z in ipairs(TC.ZonesForWorld(w)) do
                local r = tonumber(z.RequiredRebirths)
                if not z.Premium and r and r ~= math.huge and r >= need then need, zoneName = r, z.Name end
            end
        end
        if need == 0 and WG and WG.Requirement then
            local ok, req = pcall(WG.Requirement, w)
            if ok and type(req) == "table" then need = tonumber(req.Rebirths) or 0 zoneName = req.ZoneName end
        end
        local gate = WG and WG.ForWorld and WG.ForWorld(w)
        local finish = WG and WG.FinishPower and tonumber(WG.FinishPower(w)) or 0       -- "Finish Power" on the world card
        local power = tonumber(lp:GetAttribute("TrainingPower")) or 0
        return {world = w, have = reb, need = need, met = reb >= need, lastWorld = gate and gate.NextWorldId == nil,
            finish = finish, power = power, strong = power >= finish}
    end
    -- true when training should stop so the planner can act (rebirth for the requirement, or fly for the gate)
    function U.unlockAction()
        if (S.forceTrainUntil or 0) > now() then return false end
        local req = U.gateReq()
        local full = lp:GetAttribute("CanRebirth") == true
        if req.lastWorld then return full end
        if not req.met then return full end
        return req.strong
    end
    function U.world(token)
        local hi = tonumber(lp:GetAttribute("HighestUnlockedWorld")) or 1
        local cur = G.world()
        if hi <= cur then return false end
        local cfg = Cfg.WorldPortalConfig
        local portal
        for _, p in ipairs(cfg and cfg.Portals or {}) do if p.WorldId == cur then portal = p end end
        if not portal then return false end
        local m = G.path(table.unpack(portal.ModelPath))
        local cf = G.pivot(m)
        if not cf then say("Chưa thấy cổng world " .. cur) return false end
        G.tp(cf + Vector3.new(0, 4, 0), 0.6)
        local r = G.call("WorldTeleport", hi, portal.Id)
        say(r.ok and (tr("Đang sang World ", "Travelling to World ") .. hi) or (tr("Đổi world lỗi: ", "World travel failed: ") .. tostring(r.msg or r.status)))
        local t = now()
        while G.alive(token) and G.world() ~= hi and now() - t < 20 do task.wait(0.5) end
        task.wait(2)
        return G.world() == hi
    end
    local RAR = {"Mythical", "Legendary", "Epic", "Rare", "Uncommon"}
    -- paper seller NPC of the current world (server checks distance before answering shop calls)
    function U.paperSeller(w)
        local npcs = workspace:FindFirstChild("AirplaneShopNPCs")
        local npc = npcs and npcs:FindFirstChild("Shop_W" .. w)
        if npc then return npc end
        for _, p in ipairs(workspace:GetDescendants()) do
            if p:IsA("ProximityPrompt") and p.ActionText == "Open Paper Shop" then
                local m = p:FindFirstAncestorWhichIsA("Model")
                if m and (m.Name:find("W" .. w) or m.Name:find(tostring(w))) then return m end
            end
        end
        return nil
    end
    function U.buyPaper()
        local w = G.world()
        local npc = U.paperSeller(w)
        local cf = G.pivot(npc)
        if not cf then
            local gp = G.gameplay()
            local spawn = gp and gp:FindFirstChild("ProgressionSpawn")
            if spawn then G.tp(spawn.CFrame + Vector3.new(0, 4, 0), 1) end
            npc = U.paperSeller(w) cf = G.pivot(npc)
        end
        if not cf then say("Mua giấy: chưa thấy người bán giấy World " .. w) return false end
        -- stand right at the seller's prompt part and give the server time to see the new position
        local prompt = npc and npc:FindFirstChildWhichIsA("ProximityPrompt", true)
        local anchor = prompt and prompt.Parent and prompt.Parent:IsA("BasePart") and prompt.Parent.CFrame or cf
        local st
        for try = 1, 2 do
            G.tp(anchor * CFrame.new(0, 0, try == 1 and -3 or -1.5), try == 1 and 1.0 or 1.6)
            st = G.fold("GetShopState", w)
            if st.ok or not tostring(st.msg):find("Walk up") then break end
        end
        if not (st.ok and type(st.Items) == "table") then say("Mua giấy: shop không trả hàng (" .. tostring(st.msg) .. ")") return false end
        local bought = 0
        local per = {}                                        -- per rarity: count, spent, last server message
        for _, rar in ipairs(RAR) do
            local key = rar                                   -- shop items are keyed by rarity ("Uncommon")
            local it = S.opt.buyPaper[rar] and st.Items[key]
            while it and (tonumber(it.Remaining) or 0) > 0 and G.coins() >= (tonumber(it.Price) or math.huge) do
                local price = tonumber(it.Price) or 0
                local r = G.fold("BuyPaper", key, 1, Http:GenerateGUID(false), st.Cycle)
                if not r.ok then
                    say("Mua giấy lỗi: " .. tostring(r.msg))
                    notify({kind = tr("CỬA HÀNG GIẤY", "PAPER SHOP"), title = rar .. " Paper", rarity = rar, ok = false,
                        status = tr("MUA THẤT BẠI", "PURCHASE FAILED"), lines = {tostring(r.msg or r.code or "?")}})
                    if type(r.State) == "table" and r.State.Items then st = r.State end
                    break
                end
                bought += 1
                local p = per[rar] or {n = 0, spent = 0}
                per[rar] = p
                p.n += 1 p.spent += price p.msg = r.msg p.price = price
                if type(r.State) == "table" and r.State.Items then st = r.State it = st.Items[key] else it.Remaining -= 1 end
                p.left = it and tonumber(it.Remaining) or 0
                task.wait(0.3)
            end
        end
        if bought > 0 then
            say(tr("Đã mua ", "Bought ") .. bought .. tr(" giấy", " paper"))
            G.refreshProfile()
            local papers = (S.profile and S.profile.Papers) or {}
            for _, rar in ipairs(RAR) do
                local p = per[rar]
                if p then
                    local owned = tonumber(papers["W" .. w .. "_" .. rar])
                    notify({kind = tr("CỬA HÀNG GIẤY", "PAPER SHOP"), title = rar .. " Paper", rarity = rar, ok = true,
                        status = string.format(tr("ĐÃ MUA x%d", "BOUGHT x%d"), p.n),
                        lines = {
                            {tr("Thế giới", "World"), "World " .. w},
                            {tr("Giá", "Price"), "$" .. G.abbrev(p.price) .. (p.n > 1 and ("  ·  " .. tr("tổng", "total") .. " $" .. G.abbrev(p.spent)) or "")},
                            {tr("Còn trong shop", "Shop stock left"), tostring(p.left or "?")},
                            {tr("Đang có", "Owned"), owned and tostring(owned) or "?"},
                            {"Coins", "$" .. G.abbrev(G.coins())},
                            p.msg and {tr("Server", "Server"), tostring(p.msg)} or nil,
                        }})
                end
            end
        end
        return bought > 0
    end
    function U.equipBest()
        G.refreshProfile()
        local best = G.bestPlane()
        if best and not best.Equipped then
            local r = G.call("EquipPlaneId", best.Id)
            say(r.ok and (tr("Trang bị máy bay mạnh nhất: ", "Equipped strongest plane: ") .. best.Id) or (tr("Trang bị lỗi: ", "Equip failed: ") .. tostring(r.msg)))
            return r.ok
        end
        return false
    end
    U.planeSkip = {}
    function U.buyPlane()
        local PC = Cfg.PlaneConfig
        if not (PC and PC.Planes) then return false end
        G.refreshProfile()
        local owned = {}
        for _, p in ipairs((S.profile and S.profile.Planes) or {}) do owned[p.Id] = true end
        local _, bestScore = G.bestPlane()
        local mapId = "Map" .. G.world()
        local pick
        for id, cfg in pairs(PC.Planes) do
            local price = tonumber(cfg.Price) or 0
            if cfg.MapId == mapId and price > 1 and not owned[id] and not U.planeSkip[id] and price <= G.coins() then
                local sc = G.planeScore({Id = id, StarLevel = 0})
                if sc > (bestScore or 0) and (not pick or sc > pick.sc) then pick = {id = id, sc = sc, price = price} end
            end
        end
        if not pick then return false end
        local shop = G.gameplay() and G.gameplay():FindFirstChild("PlaneShop")
        local cf = G.pivot(shop)
        if cf then G.tp(cf + Vector3.new(0, 4, 0), 0.5) end
        local r = G.call("BuyPlane", pick.id)
        if r.ok then say("Mua máy bay " .. pick.id .. " (" .. pick.price .. ")") U.equipBest()
        else U.planeSkip[pick.id] = true say("Không mua được " .. pick.id .. ": " .. tostring(r.msg)) end
        return r.ok
    end
    -- --- folding: Enter -> Start(paperKey) -> Challenge/Hit loop (perfect timestamps) -> Ack
    local PFC = Cfg.PaperFoldingConfig
    local function perfectTime(c, nowT)
        if c.Kind == "Circle" then
            local tr = tonumber(c.TargetRingRadius) or 0.32
            local t = c.Start + (c.StartRadius - tr) * c.Duration / c.StartRadius
            return math.max(t, nowT + 0.03)
        end
        local x = tonumber(c.Center) or 0.5
        if c.Dir == -1 then x = 1 - x end
        local per = c.Period
        local base = math.max(c.Start, nowT + 0.06)
        local k = math.floor((base - c.Start) / (2 * per))
        for kk = k, k + 3 do
            for _, v in ipairs({x, 2 - x}) do
                local t = c.Start + per * (2 * kk + v)
                if t >= base then return t end
            end
        end
        return base
    end
    function U.foldOne(token, key, started)
        local rarity = key:match("_(%a+)$") or key          -- server expects the paper rarity ("Epic"), not "W2_Epic"
        local s = started or G.fold("Start", rarity)
        if not s.ok and not tostring(s.msg):find("aper") then s = G.fold("Start", key) end
        if not s.ok then say("Gấp " .. key .. " lỗi: " .. tostring(s.msg)) return false end
        local sid = s.SessionId
        say(tr("Đang gấp ", "Folding ") .. key)
        local result
        local grades = {}
        for _ = 1, 20 do
            if not S.alive then return false end
            local c
            for _ = 1, 30 do
                c = G.fold("Challenge", sid)
                if c.ok or not c.wait then break end
                task.wait(math.clamp(tonumber(c.retryIn) or 0.2, 0.05, 1))
            end
            if not (c and c.ok) then say("Thử thách gấp lỗi: " .. tostring(c and c.msg)) return false end
            local target = perfectTime(c, workspace:GetServerTimeNow())
            while S.alive and workspace:GetServerTimeNow() < target do task.wait() end
            local h = G.fold("Hit", sid, c.Index, workspace:GetServerTimeNow())
            if not h.ok then say("Gấp hụt: " .. tostring(h.msg)) return false end
            grades[#grades + 1] = tostring(h.Grade or "?") .. "(" .. tostring(h.Pct and math.floor(tonumber(h.Pct) or 0) or "?") .. ")"
            if h.Done then result = h break end
            task.wait(0.15)
        end
        if result then
            pcall(G.fold, "Ack", result.SessionId or sid)
            S.stats.folds += 1
            local plane = result.PlaneId or (type(result.Result) == "table" and (result.Result.PlaneId or result.Result.Id)) or "?"
            local perfect = 0
            for _, g in ipairs(grades) do if g:find("PERFECT") then perfect += 1 end end
            say(string.format(tr("Gấp xong %s → %s · Perfect %d/%d · hạng %s", "Folded %s → %s · Perfect %d/%d · rank %s"),key, tostring(plane), perfect, #grades,
                tostring(result.Rank or result.FoldRank or result.Grade or (result.Accuracy and (math.floor(result.Accuracy) .. "%")) or "?")))
            say("  điểm từng bước: " .. table.concat(grades, " "))
            -- notification card: the same facts the game's "YOU GOT!" screen shows
            local res = type(result.Result) == "table" and result.Result or result
            local pf = planeFacts(plane)
            local chance = tonumber(res.Chance)
            local rank = tostring(result.Rank or "?")
            local acc = tonumber(result.Accuracy)
            local qty = tonumber(res.Quantity) or 1
            notify({kind = tr("GẤP MÁY BAY", "PLANE FOLDED"), title = pf.name, rarity = res.Rarity or pf.rarity, ok = true,
                status = res.Duplicate and string.format(tr("TRÙNG +1 · x%d", "DUPLICATE +1 · x%d"), qty) or tr("MÁY BAY MỚI!", "NEW PLANE!"),
                lines = {
                    {tr("Độ hiếm", "Rarity"), tostring(res.Rarity or pf.rarity) .. (chance and string.format("  (%s%%)", chance < 0.001 and "<0.1" or string.format(chance >= 0.1 and "%.1f" or "%.2f", chance * 100)) or "")},
                    {tr("Lực máy bay", "Plane Power"), "+" .. G.abbrev(pf.power)},
                    {"Base Power", G.abbrev(pf.base)},
                    {tr("Tốc độ / Coins", "Speed / Coins"), string.format("x%.2f  /  x%.2f", pf.speed, pf.coins)},
                    {tr("Hạng gấp", "Fold rank"), rank .. (acc and string.format(" · %d%%", math.floor(acc)) or "") .. string.format(" · Perfect %d/%d", perfect, #grades)},
                    {tr("Giấy", "Paper"), key .. ((tonumber(res.LuckMultiplier) or 1) > 1 and string.format(" · Luck x%.2f", res.LuckMultiplier) or "")},
                }})
            return true
        end
        return false
    end
    function U.fold(token)
        G.refreshProfile()
        local papers = (S.profile and S.profile.Papers) or {}
        local w = G.world()
        local key
        for _, rar in ipairs(RAR) do
            local k = "W" .. w .. "_" .. rar
            if S.opt.fold[rar] and (tonumber(papers[k]) or 0) > 0 then key = k break end
        end
        if not key then return false end
        -- 1) try straight from where we stand (no table, no menu); 2) fall back to the table only if the server insists
        local ok
        if U.foldRemote ~= false then
            local rarity = key:match("_(%a+)$") or key
            local probe = G.fold("Start", rarity)
            if probe.ok then
                if U.foldRemote == nil then say("Gấp từ xa được server chấp nhận — không cần tới bàn") end
                U.foldRemote = true
                ok = U.foldOne(token, key, probe)            -- continue the session we just opened
            else
                say("Gấp từ xa bị từ chối: " .. tostring(probe.msg) .. " → tới bàn gấp")
                U.foldRemote = false
            end
        end
        if ok == nil then
            local gp = G.gameplay()
            local tables = gp and gp:FindFirstChild("PaperFoldingTables")
            local tbl = tables and tables:GetChildren()[1]
            local cf = G.pivot(tbl)
            if cf then G.tp(cf * CFrame.new(0, 2, 4), 0.5) end
            local e = G.fold("Enter")
            if not e.ok then say("Bàn gấp: " .. tostring(e.msg or (e.far and "quá xa") or (e.full and "đã đầy"))) return false end
            ok = U.foldOne(token, key)
        end
        task.wait(0.3)
        G.leaveFolding()          -- unlock the character + close the game's paper picker
        U.equipBest()
        return ok
    end
    -- --- fuse: strongest plane as target, weaker spares as materials
    function U.fuse()
        G.refreshProfile()
        local planes = (S.profile and S.profile.Planes) or {}
        local target
        if S.opt.fuse ~= "auto" then
            for _, p in ipairs(planes) do if p.Uid == S.opt.fuse then target = p end end
        end
        target = target or G.bestPlane()
        if not target then return false end
        local FC
        local fm = Shared:FindFirstChild("PlaneFusionConfig")
        if fm then local ok, v = pcall(require, fm) if ok then FC = v end end
        local pool = {}
        local tcfg = Cfg.PlaneConfig and Cfg.PlaneConfig.Get(target.Id)
        local map = tcfg and tcfg.MapId
        for _, p in ipairs(planes) do
            local protected = FC and FC.IsProtectedPlane and FC.IsProtectedPlane(p.Id)
            local pcfg = Cfg.PlaneConfig and Cfg.PlaneConfig.Get(p.Id)
            local sameWorld = not map or not pcfg or pcfg.MapId == map            -- server: "InvalidWorld" for cross-world materials
            if p.Uid ~= target.Uid and not p.Equipped and not p.Locked and not protected and sameWorld then pool[#pool + 1] = p end
        end
        if #pool == 0 then return false end
        table.sort(pool, function(a, b) return G.planeScore(a) < G.planeScore(b) end)
        local mats, n = {}, 0
        for _, p in ipairs(pool) do
            local q = math.max(1, tonumber(p.Quantity) or 1)
            for _ = 1, q do if n < 5 then mats[p.Uid] = (mats[p.Uid] or 0) + 1 n += 1 end end
        end
        local q = G.call("PlaneFusion", "Quote", target.Uid, mats)
        if not q.ok then say("Fuse: " .. tostring(q.msg)) return false end
        local qd = type(q.data) == "table" and q.data or q
        local nmatAll = 0 for _, k in pairs(mats) do nmatAll += k end
        local tfacts = planeFacts(target.Id)
        local cost = tonumber(qd.Cost or qd.Price)
        if not cost and FC and FC.GetFuseCost then
            local okC, c = pcall(FC.GetFuseCost, FC.NormalizeRarity and FC.NormalizeRarity(tfacts.rarity) or tfacts.rarity, nmatAll, target.Id)
            cost = okC and tonumber(c) or nil
        end
        cost = cost or 0
        if cost > G.coins() then return false end
        local m = G.path("World " .. G.world(), "PlaneFusionMachine_W" .. G.world())
        local cf = G.pivot(m)
        if cf then G.tp(cf + Vector3.new(0, 4, 6), 0.5) end
        local guid = Http:GenerateGUID(false)
        local r = G.call("PlaneFusion", "Fuse", guid, target.Uid, mats)
        if not r.ok and (r.msg == "Server didn't respond." or r.code == "ServerError") then
            task.wait(1) r = G.call("PlaneFusion", "Result", guid)
        end
        S.stats.fuses += 1
        local res = type(r.data) == "table" and r.data or r
        local okFuse = res.Success or res.success or res.Upgraded or (res.NewStar and res.NewStar > (target.StarLevel or 0))
        local nmat = 0 for _ in pairs(mats) do nmat += 1 end
        local chance = tonumber(qd.SuccessPercent or qd.Chance or qd.Percent)
        say(r.ok and string.format("Fuse %s (%d nguyên liệu, tỉ lệ %s%%): %s", target.Id, nmat, chance and tostring(chance) or "?",
                okFuse and "THÀNH CÔNG" or (okFuse == false and "trượt" or "đã gửi"))
            or ("Fuse lỗi: " .. tostring(r.msg)))
        if r.ok then
            local keys = {}
            for k, v in pairs(res) do if type(v) ~= "table" then keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end end
            say("  fuse kết quả: " .. table.concat(keys, ", "))
        end
        -- notification card: result + full plane facts + what was used
        do
            local starBefore = tonumber(target.StarLevel) or 0
            local starAfter = tonumber(res.StarLevel) or (res.Success and starBefore + 1 or starBefore)
            local mult = 1
            if FC and FC.GetStatMultiplier then
                local okM, m = pcall(FC.GetStatMultiplier, res.Success and starAfter or starBefore)
                mult = okM and tonumber(m) or 1
            end
            local matNames = {}
            for uid, k in pairs(mats) do
                for _, p in ipairs(planes) do
                    if p.Uid == uid then
                        matNames[#matNames + 1] = planeFacts(p.Id).name .. ((tonumber(p.StarLevel) or 0) > 0 and (" " .. p.StarLevel .. "★") or "") .. " x" .. k
                        break
                    end
                end
            end
            local stars = function(n) return n > 0 and (n .. "★") or "0★" end
            local status
            if not r.ok then status = tr("FUSE LỖI", "FUSE ERROR")
            elseif res.Success then status = string.format(tr("FUSE THÀNH CÔNG  %s → %s", "FUSION SUCCESS  %s → %s"), stars(starBefore), stars(starAfter))
            else status = tr("FUSE THẤT BẠI · máy bay vẫn an toàn", "FUSION FAILED · plane is safe") end
            notify({kind = "AUTO FUSE", title = tfacts.name, rarity = tfacts.rarity, ok = r.ok and res.Success == true,
                status = status,
                lines = {
                    {tr("Độ hiếm / Sao", "Rarity / Stars"), tfacts.rarity .. " · " .. stars(res.Success and starAfter or starBefore)},
                    {tr("Tỉ lệ thành công", "Success chance"), chance and (tostring(chance) .. "%") or "?"},
                    {tr("Lực máy bay", "Plane Power"), "+" .. G.abbrev(tfacts.power) .. (mult ~= 1 and string.format("  (★ x%.2f)", mult) or "")},
                    {tr("Tốc độ / Coins", "Speed / Coins"), string.format("x%.2f  /  x%.2f", tfacts.speed, tfacts.coins)},
                    {tr("Chi phí", "Cost"), "$" .. G.abbrev(cost)},
                    {tr("Nguyên liệu", "Materials"), #matNames > 0 and table.concat(matNames, ", ") or tostring(nmat)},
                    (not r.ok) and {tr("Lỗi", "Error"), tostring(r.msg or r.code)} or nil,
                }})
        end
        task.wait(1.5)
        return r.ok
    end
    -- --- Halloween candy exchange
    function U.exchange()
        local ev = RS:FindFirstChild("HalloweenEvent")
        local er = ev and ev:FindFirstChild("ExchangeRequest")
        if not er then return false end
        local ok, st = pcall(er.InvokeServer, er, "State")
        if not (ok and type(st) == "table" and type(st.List) == "table") then return false end
        local candy = tonumber(st.Candy) or tonumber(lp:GetAttribute("HalloweenCandy")) or 0
        local done = 0
        U.eventList = st.List
        local picked = next(S.opt.event) ~= nil
        for _, it in ipairs(st.List) do
            if picked and not S.opt.event[tostring(it.Id)] then continue end
            local price = tonumber(it.Price) or math.huge
            local left = it.Left == nil and 1 or (tonumber(it.Left) or 0)
            while not it.SoldOut and left > 0 and candy >= price do
                local ok2, r = pcall(er.InvokeServer, er, "Buy", it.Id)
                if not (ok2 and type(r) == "table" and r.ok ~= false) then break end
                candy -= price left -= 1 done += 1
                say(tr("Đổi kẹo: ", "Candy exchange: ") .. tostring(it.Name or it.Id))
                task.wait(0.4)
            end
        end
        return done > 0
    end
end

-- ============================================================ REWARDS (no character needed)
local W = {}
do
    W.CODES = {"RELEASE", "UPDATE", "UPDATE1", "HALLOWEEN", "CANDY", "SPOOKY", "1KLIKES", "5KLIKES", "10KLIKES", "1KFAVORITES",
        "100KVISITS", "1MVISITS", "THANKYOU", "PAPER", "PLANE", "FREE", "AURA", "WORLD2", "BHSTUDIO"}
    for _, c in ipairs(env.DYX_EXTRA_CODES or {}) do table.insert(W.CODES, 1, c) end
    local triedFile = "DYX_paper_codes.json"
    local tried = {}
    pcall(function() tried = Http:JSONDecode(readfile(triedFile)) end)
    function W.codes()
        -- server rate-limits redeem ("SLOW"): wait between codes and retry SLOW ones; only final statuses are remembered
        local n, count = 0, 0
        for _, code in ipairs(W.CODES) do
            if not tried[code] and S.alive then
                count += 1
                local st
                for attempt = 1, 4 do
                    local r = G.call("RedeemCode", code)
                    st = r.ok and "OK" or tostring(r.status or r.msg or "fail")
                    if r.ok then n += 1 say("Code " .. code .. ": " .. tostring(r.reward and r.reward.Text or "đã nhận")) end
                    if st ~= "SLOW" then break end
                    task.wait(6 * attempt)
                end
                if st ~= "SLOW" then tried[code] = st end
                task.wait(6)
            end
        end
        pcall(writefile, triedFile, Http:JSONEncode(tried))
        return n, count
    end
    W.ptFail = {}
    function W.playtime()
        local r = G.call("GetPlaytimeRewards")
        local st = r.state or (r.data and r.data.state)
        if not (st and st.Rewards) then say("Quà giờ chơi: không đọc được trạng thái (" .. tostring(r.msg) .. ")") return end
        local playSeconds = tonumber(st.Seconds) or 0
        for _, rw in ipairs(st.Rewards) do
            local ready = rw.Ready or (not rw.Claimed and playSeconds >= (tonumber(rw.Seconds) or math.huge))
            if ready and not rw.Claimed and (W.ptFail[rw.Id] or 0) < now() then
                local c = G.call("ClaimPlaytimeReward", rw.Id)
                if c.ok then
                    say(tr("Nhận quà giờ chơi: ", "Playtime reward: ") .. tostring(rw.Name))
                else
                    W.ptFail[rw.Id] = now() + 60          -- e.g. "Complete this quest first" — retry later, don't spam
                    say("Quà giờ chơi " .. tostring(rw.Name) .. ": " .. tostring(c.msg or c.status or "bị từ chối"))
                end
                task.wait(0.6)
            end
        end
    end
    function W.daily()
        local r = G.call("GetDailyRewards")
        local st = r.state
        if not (st and st.CanClaim) then return end
        local cfg = Cfg.DailyRewardConfig and Cfg.DailyRewardConfig.Rewards and Cfg.DailyRewardConfig.Rewards[st.CurrentDayIndex]
        local pickWorld = cfg and cfg.ChooseWorld and (st.HighestWorld or G.world()) or nil
        local c = G.call("ClaimDailyReward", st.ClaimToken, pickWorld)
        say(c.ok and tr("Nhận quà hằng ngày", "Daily reward claimed") or (tr("Quà ngày: ", "Daily reward: ") .. tostring(c.msg)))
    end
    W.dailyNote = 0
    function W.community()
        local cr = R:FindFirstChild("CommunityReward")
        if not cr then return end
        local ok, st = pcall(cr.InvokeServer, cr, "State")
        if ok and type(st) == "table" and st.InGroup and not st.Claimed then
            pcall(cr.InvokeServer, cr, "Claim", {Favorited = false})
            say("Nhận quà cộng đồng")
        end
    end
end

-- ============================================================ GUI  (DYXNET // CYBER COMMAND DECK)
local UI = {}
do
    local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
    local C = {
        void        = rgb(5, 7, 11),
        bg          = rgb(8, 10, 15),
        grid        = rgb(12, 15, 22),
        sidebar     = rgb(10, 13, 19),
        card        = rgb(13, 16, 24),
        cardHover   = rgb(18, 22, 33),
        cardOn      = rgb(23, 11, 18),
        border      = rgb(26, 32, 46),
        borderSoft  = rgb(20, 25, 36),
        crimson     = rgb(242, 35, 69),
        crimsonGlow = rgb(230, 18, 56),
        crimsonSoft = rgb(255, 195, 204),
        crimsonDark = rgb(48, 13, 24),
        emerald     = rgb(16, 185, 129),
        emeraldDark = rgb(10, 42, 32),
        amber       = rgb(245, 158, 11),
        ink         = rgb(226, 230, 237),
        sub         = rgb(142, 152, 174),
        muted       = rgb(88, 98, 118),
        trackOff    = rgb(32, 38, 52),
    }
    UI.C = C

    local function new(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props or {}) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local function corner(p, r) new("UICorner", {CornerRadius = typeof(r) == "UDim" and r or UDim.new(0, r or 6)}, p) end
    local function stroke(p, c, t, trans)
        return new("UIStroke", {
            Color = c or C.border,
            Thickness = t or 1,
            Transparency = trans or 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, p)
    end
    local function tween(obj, dur, props, style, dir)
        local t = Tween:Create(
            obj,
            TweenInfo.new(dur or 0.16, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out),
            props
        )
        t:Play()
        return t
    end
    local function label(p, props)
        props.BackgroundTransparency = 1
        props.Font = props.Font or Enum.Font.GothamBold
        props.TextColor3 = props.TextColor3 or C.ink
        props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
        return new("TextLabel", props, p)
    end

    -- ========================================================================
    -- CUSTOM ASSET & BASE64 PIPELINE (Logo PNG & 4x Supersampled SVG Atlas)
    -- ========================================================================
    local logoAssetUri, logoIsFull1080p, svgAtlasUri
    do
        local LOGO_WIN_PATH = "C:\\Users\\danh8\\Downloads\\DyxNet\\design\\logo-animation\\dyxnet-cyber-logo-v1.png"
        local LOGO_SQ_FILE = "dyxnet_cyber_logo_160_v2.png"
        local SVG_ATLAS_FILE = "dyxnet_cyber_svg_atlas_v1.png"
        local LOGO_B64 = "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"
        local ATLAS_B64 = "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"

        local function b64decode(data)
            if type(crypt) == "table" and type(crypt.base64decode) == "function" then
                local ok, res = pcall(crypt.base64decode, data)
                if ok and type(res) == "string" and #res > 0 then return res end
            end
            if type(env.base64decode) == "function" then
                local ok, res = pcall(env.base64decode, data)
                if ok and type(res) == "string" and #res > 0 then return res end
            end
            local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            local map = {}
            for i = 1, #b do map[b:sub(i, i)] = i - 1 end
            local out = table.create(math.floor(#data * 0.75))
            local n, val, bits = 0, 0, 0
            for i = 1, #data do
                local v = map[data:sub(i, i)]
                if v ~= nil then
                    val = val * 64 + v
                    bits += 6
                    if bits >= 8 then
                        bits -= 8
                        local byte = math.floor(val / (2 ^ bits)) % 256
                        val = val % (2 ^ bits)
                        n += 1
                        out[n] = string.char(byte)
                    end
                end
            end
            return table.concat(out)
        end

        local getAsset = (type(getcustomasset) == "function" and getcustomasset)
            or (type(getsynasset) == "function" and getsynasset)

        local function resolveAsset(winPath, localFile, b64Fallback)
            if not getAsset then return nil, false end
            if localFile and type(isfile) == "function" then
                local okExists, exists = pcall(isfile, localFile)
                if okExists and exists then
                    local okUri, uri = pcall(getAsset, localFile)
                    if okUri and type(uri) == "string" and #uri > 0 then
                        return uri, false
                    end
                end
            end
            if localFile and b64Fallback and type(writefile) == "function" then
                pcall(function() writefile(localFile, b64decode(b64Fallback)) end)
                local okUri, uri = pcall(getAsset, localFile)
                if okUri and type(uri) == "string" and #uri > 0 then
                    return uri, false
                end
            end
            if winPath then
                local ok, uri = pcall(getAsset, winPath)
                if ok and type(uri) == "string" and #uri > 0 then
                    return uri, true
                end
            end
            return nil, false
        end

        logoAssetUri, logoIsFull1080p = resolveAsset(LOGO_WIN_PATH, LOGO_SQ_FILE, LOGO_B64)
        svgAtlasUri = select(1, resolveAsset(nil, SVG_ATLAS_FILE, ATLAS_B64))
    end

    -- ========================================================================
    -- DUAL-ENGINE SVG ICON SYSTEM (4x Supersampled SVG Atlas + Vector Fallback)
    -- ========================================================================
    local SVG_INDEX = {
        farm = 0, throw = 1, collect = 2, player = 3, train = 4,
        idle = 5, upgrade = 6, seed = 7, bar = 8, expand = 9,
        rewards = 10, daily = 11, all = 12, bolt = 13, stop = 14,
        terminal = 15, wallet = 16, minimize = 17, close = 18, restore = 19,
    }
    local SVG_VECTORS = {
        farm = {
            {"L",12,21,12,10}, {"L",7,21,17,21},
            {"L",12,14,7,11}, {"L",7,11,5,6}, {"L",5,6,10,7}, {"L",10,7,12,12},
            {"L",12,11,17,8}, {"L",17,8,19,3}, {"L",19,3,14,4}, {"L",14,4,12,9},
        },
        throw = {
            {"C",12,12,7}, {"C",12,12,2.2},
            {"L",12,2,12,6}, {"L",12,18,12,22}, {"L",2,12,6,12}, {"L",18,12,22,12},
        },
        collect = {
            {"L",4,15,4,19}, {"L",4,19,20,19}, {"L",20,19,20,15},
            {"L",12,3,12,14}, {"L",8,10,12,14}, {"L",16,10,12,14}, {"L",7,6,17,6},
        },
        player = {
            {"C",12,7.5,3.8},
            {"L",5,20,6.5,15.5}, {"L",6.5,15.5,17.5,15.5}, {"L",17.5,15.5,19,20},
        },
        train = {
            {"L",6.5,12,17.5,12}, {"R",3.5,7,6.5,17}, {"R",17.5,7,20.5,17},
            {"L",1.5,9.5,1.5,14.5}, {"L",22.5,9.5,22.5,14.5},
        },
        idle = {
            {"L",12,2.5,4.5,6}, {"L",4.5,6,4.5,12}, {"L",4.5,12,12,21.5},
            {"L",12,21.5,19.5,12}, {"L",19.5,12,19.5,6}, {"L",19.5,6,12,2.5},
            {"L",9,12,11.2,14.2}, {"L",11.2,14.2,15.5,9.5},
        },
        upgrade = {
            {"L",5,17,12,10}, {"L",12,10,19,17},
            {"L",5,11,12,4}, {"L",12,4,19,11}, {"L",12,10,12,21},
        },
        seed = {
            {"L",12,2.5,19.5,7}, {"L",19.5,7,19.5,17}, {"L",19.5,17,12,21.5},
            {"L",12,21.5,4.5,17}, {"L",4.5,17,4.5,7}, {"L",4.5,7,12,2.5},
            {"C",12,12,3.2}, {"L",12,2.5,12,8.8},
        },
        bar = {
            {"L",4,21,4,5}, {"L",20,21,20,5}, {"L",2,5,22,5},
            {"L",2,21,7,21}, {"L",17,21,22,21},
            {"L",9,5,9,10}, {"L",15,5,15,10}, {"C",12,12.5,2.2},
        },
        expand = {
            {"L",15,3,21,3}, {"L",21,3,21,9}, {"L",21,3,14,10},
            {"L",9,21,3,21}, {"L",3,21,3,15}, {"L",3,21,10,14},
            {"L",21,15,21,21}, {"L",21,21,15,21}, {"L",21,21,14,14},
            {"L",3,9,3,3}, {"L",3,3,9,3}, {"L",3,3,10,10},
        },
        rewards = {
            {"R",3.5,8,20.5,12}, {"R",5,12,19,20.5}, {"L",12,8,12,20.5},
            {"L",12,8,7.5,4.5}, {"L",12,8,16.5,4.5},
        },
        daily = {
            {"R",3.5,5,20.5,20.5}, {"L",3.5,9.5,20.5,9.5},
            {"L",8,2.5,8,6.5}, {"L",16,2.5,16,6.5},
            {"L",8.5,15,11,17.5}, {"L",11,17.5,16,12.5},
        },
        all = {
            {"R",3.5,3.5,10.5,10.5}, {"R",13.5,3.5,20.5,10.5},
            {"R",3.5,13.5,10.5,20.5}, {"R",13.5,13.5,20.5,20.5},
        },
        bolt = {
            {"L",13,2.5,5.5,13.5}, {"L",5.5,13.5,12,13.5},
            {"L",12,13.5,11,21.5}, {"L",11,21.5,18.5,10.5},
            {"L",18.5,10.5,12,10.5}, {"L",12,10.5,13,2.5},
        },
        stop = {
            {"L",8.5,3,15.5,3}, {"L",15.5,3,21,8.5}, {"L",21,8.5,21,15.5},
            {"L",21,15.5,15.5,21}, {"L",15.5,21,8.5,21}, {"L",8.5,21,3,15.5},
            {"L",3,15.5,3,8.5}, {"L",3,8.5,8.5,3}, {"R",9,9,15,15},
        },
        terminal = {
            {"R",3,4,21,20}, {"L",7,9,10.5,12}, {"L",10.5,12,7,15}, {"L",12.5,15,17,15},
        },
        wallet = {
            {"C",12,12,8.5}, {"L",12,6,12,18},
            {"L",15,9,9.5,9}, {"L",9.5,9,9.5,12}, {"L",9.5,12,14.5,12},
            {"L",14.5,12,14.5,15}, {"L",14.5,15,9,15},
        },
        minimize = { {"L",5,12,19,12} },
        close = { {"L",6,6,18,18}, {"L",18,6,6,18} },
        restore = {
            {"L",14,4,20,4}, {"L",20,4,20,10}, {"L",20,4,13,11},
            {"L",10,20,4,20}, {"L",4,20,4,14}, {"L",4,20,11,13},
        },
        key = {
            {"C",7.5,12,4.2},
            {"L",11.7,12,21.5,12},
            {"L",17,12,17,16.2},
            {"L",20.2,12,20.2,15.5},
        },
    }

    function UI.icon(parent, name, x, y, size, color)
        local holder = new("Frame", {
            Name = "Svg_" .. tostring(name),
            Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(size, size),
            BackgroundTransparency = 1,
        }, parent)

        local idx = SVG_INDEX[name]
        if svgAtlasUri and idx then
            local col = idx % 5
            local row = math.floor(idx / 5)
            local imgLayer = new("ImageLabel", {
                Name = "AtlasLayer",
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                Image = svgAtlasUri,
                ImageColor3 = color,
                ImageRectOffset = Vector2.new(col * 48, row * 48),
                ImageRectSize = Vector2.new(48, 48),
                ScaleType = Enum.ScaleType.Stretch,
            }, holder)
            return {
                frame = holder,
                setColor = function(newColor)
                    imgLayer.ImageColor3 = newColor
                end,
            }
        end

        local vecLayer = new("Frame", {
            Name = "VectorLayer",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
        }, holder)
        local paintTargets, strokeTargets = {}, {}
        local sc = size / 24
        local thickness = math.max(1.5, math.floor(1.85 * sc + 0.5))
        for _, cmd in ipairs(SVG_VECTORS[name] or SVG_VECTORS.all) do
            local kind = cmd[1]
            if kind == "L" then
                local x1, y1, x2, y2 = cmd[2] * sc, cmd[3] * sc, cmd[4] * sc, cmd[5] * sc
                local dx, dy = x2 - x1, y2 - y1
                local len = math.sqrt(dx * dx + dy * dy)
                local seg = new("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromOffset((x1 + x2) * 0.5, (y1 + y2) * 0.5),
                    Size = UDim2.fromOffset(len + thickness * 0.45, thickness),
                    Rotation = math.deg(math.atan2(dy, dx)),
                    BackgroundColor3 = color,
                    BorderSizePixel = 0,
                }, vecLayer)
                corner(seg, UDim.new(1, 0))
                paintTargets[#paintTargets + 1] = seg
            elseif kind == "R" then
                local x1, y1, x2, y2 = cmd[2] * sc, cmd[3] * sc, cmd[4] * sc, cmd[5] * sc
                local box = new("Frame", {
                    Position = UDim2.fromOffset(x1, y1),
                    Size = UDim2.fromOffset(x2 - x1, y2 - y1),
                    BackgroundTransparency = 1,
                }, vecLayer)
                corner(box, math.max(1, math.floor(1.5 * sc)))
                strokeTargets[#strokeTargets + 1] = stroke(box, color, thickness)
            elseif kind == "C" then
                local cx, cy, r = cmd[2] * sc, cmd[3] * sc, cmd[4] * sc
                local cir = new("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromOffset(cx, cy),
                    Size = UDim2.fromOffset(r * 2, r * 2),
                    BackgroundTransparency = 1,
                }, vecLayer)
                corner(cir, UDim.new(1, 0))
                strokeTargets[#strokeTargets + 1] = stroke(cir, color, thickness)
            end
        end
        return {
            frame = holder,
            setColor = function(newColor)
                for _, f in ipairs(paintTargets) do f.BackgroundColor3 = newColor end
                for _, s in ipairs(strokeTargets) do s.Color = newColor end
            end,
        }
    end

    -- ========================================================================
    -- SQUARE DYXNET LOGO BUILDER (Auto-Cropped 1:1 from dyxnet-cyber-logo-v1.png)
    -- ========================================================================
    local D_PATHS = {
        {pts={ {827,270},{1025,270},{1100,345},{1100,470},{1025,545},{827,545},{827,270} }, w=7},
        {pts={ {869,313},{1007,313},{1055,361},{1055,451},{1007,499},{869,499} }, w=3},
        {pts={ {890,356},{960,356},{1008,405},{960,454},{890,454},{939,405},{890,356} }, w=5},
    }

    function UI.logo(parent, x, y, boxSize)
        local box = new("Frame", {
            Name = "DyxNetSquareLogo",
            Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(boxSize, boxSize),
            BackgroundColor3 = C.void,
            BorderSizePixel = 0,
            ClipsDescendants = true,
        }, parent)
        local cRad = UDim.new(0, math.max(6, math.floor(boxSize * 0.16)))
        corner(box, cRad)
        stroke(box, C.crimson, 1, 0.45)

        if logoAssetUri then
            local img = new("ImageLabel", {
                Name = "LogoImage",
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                Image = logoAssetUri,
                ScaleType = Enum.ScaleType.Crop,
            }, box)
            if logoIsFull1080p then
                img.ScaleType = Enum.ScaleType.Stretch
                img.ImageRectOffset = Vector2.new(642, 182)
                img.ImageRectSize = Vector2.new(640, 640)
            end
            corner(img, cRad)
            return box
        end

        local vecRoot = new("Frame", {
            Name = "VectorLogo",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
        }, box)
        local cropX, cropY, cropS = 642, 182, 640
        local sc = boxSize / cropS
        for _, path in ipairs(D_PATHS) do
            local pts = path.pts
            local thick = math.max(1.2, path.w * sc)
            for i = 1, #pts - 1 do
                local x1, y1 = (pts[i][1] - cropX) * sc, (pts[i][2] - cropY) * sc
                local x2, y2 = (pts[i+1][1] - cropX) * sc, (pts[i+1][2] - cropY) * sc
                local dx, dy = x2 - x1, y2 - y1
                local len = math.sqrt(dx * dx + dy * dy)
                local seg = new("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromOffset((x1 + x2) * 0.5, (y1 + y2) * 0.5),
                    Size = UDim2.fromOffset(len + thick * 0.4, thick),
                    Rotation = math.deg(math.atan2(dy, dx)),
                    BackgroundColor3 = C.crimson,
                    BorderSizePixel = 0,
                }, vecRoot)
                corner(seg, UDim.new(1, 0))
            end
        end
        new("TextLabel", {
            Position = UDim2.fromOffset(0, math.floor((603 - cropY) * sc)),
            Size = UDim2.new(1, 0, 0, math.max(8, math.floor(96 * sc))),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            Text = "DYXNET",
            TextColor3 = C.ink,
            TextSize = math.max(6, math.floor(72 * sc)),
        }, vecRoot)
        return box
    end

    local function buildGrid(target, w, h, step, col, trans, z)
        local g = new("Frame", {
            Name = "GridLayer",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            ZIndex = z or 0,
        }, target)
        for gx = step, w - 1, step do
            new("Frame", {
                Position = UDim2.fromOffset(gx, 0),
                Size = UDim2.fromOffset(1, h),
                BackgroundColor3 = col,
                BackgroundTransparency = trans,
                BorderSizePixel = 0,
                ZIndex = z or 0,
            }, g)
        end
        for gy = step, h - 1, step do
            new("Frame", {
                Position = UDim2.fromOffset(0, gy),
                Size = UDim2.fromOffset(w, 1),
                BackgroundColor3 = col,
                BackgroundTransparency = trans,
                BorderSizePixel = 0,
                ZIndex = z or 0,
            }, g)
        end
    end

    local function addTopLaser(target, z)
        local line = new("Frame", {
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.new(1, 0, 0, 2),
            BackgroundColor3 = C.crimson,
            BorderSizePixel = 0,
            ZIndex = z or 4,
        }, target)
        new("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.85),
                NumberSequenceKeypoint.new(0.18, 0),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(0.82, 0),
                NumberSequenceKeypoint.new(1, 0.85),
            })
        }, line)
    end

    local function addCornerBrackets(parent, len, thick, color, trans)
        len = len or 14
        thick = thick or 2
        color = color or C.crimson
        trans = trans or 0.25
        for _, c in ipairs({
            {ax=0, ay=0, px=0, py=0},
            {ax=1, ay=0, px=1, py=0},
            {ax=0, ay=1, px=0, py=1},
            {ax=1, ay=1, px=1, py=1},
        }) do
            new("Frame", {
                AnchorPoint = Vector2.new(c.ax, c.ay),
                Position = UDim2.new(c.px, 0, c.py, 0),
                Size = UDim2.fromOffset(len, thick),
                BackgroundColor3 = color,
                BackgroundTransparency = trans,
                BorderSizePixel = 0,
            }, parent)
            new("Frame", {
                AnchorPoint = Vector2.new(c.ax, c.ay),
                Position = UDim2.new(c.px, 0, c.py, 0),
                Size = UDim2.fromOffset(thick, len),
                BackgroundColor3 = color,
                BackgroundTransparency = trans,
                BorderSizePixel = 0,
            }, parent)
        end
    end

    local function makeIconButton(parent, svgName, x, y, w, h, bgCol, iconCol, hoverBg)
        local btn = new("TextButton", {
            Text = "",
            AutoButtonColor = false,
            Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(w, h),
            BackgroundColor3 = bgCol,
            BorderSizePixel = 0,
        }, parent)
        corner(btn, 7)
        local st = stroke(btn, C.border, 1)
        local ico = UI.icon(btn, svgName, math.floor((w - 16) * 0.5), math.floor((h - 16) * 0.5), 16, iconCol)
        on(btn.MouseEnter, function()
            tween(btn, 0.14, {BackgroundColor3 = hoverBg})
            st.Color = C.crimson
            ico.setColor(C.ink)
        end)
        on(btn.MouseLeave, function()
            tween(btn, 0.14, {BackgroundColor3 = bgCol})
            st.Color = C.border
            ico.setColor(iconCol)
        end)
        return btn
    end

    -- ========================================================================
    -- SCREEN GUI & MAIN PANEL (560x392)
    -- ========================================================================
    local gui = new("ScreenGui", {
        Name = "DYXNET_PaperOps",
        ResetOnSpawn = false,
        DisplayOrder = 2500,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
    })
    local okParent = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not okParent or not gui.Parent then gui.Parent = lp:WaitForChild("PlayerGui") end
    UI.gui = gui

    -- ========================================================================
    -- RIGHT-SIDE NOTIFICATION CARDS (paper bought · plane folded · fuse result)
    -- ========================================================================
    do
        local RCOL = {Common = rgb(190, 198, 212), Uncommon = rgb(74, 222, 128), Rare = rgb(56, 189, 248), Epic = rgb(192, 132, 252),
            Legendary = rgb(251, 191, 36), Mythical = rgb(244, 63, 94), Secret = rgb(255, 255, 255)}
        local PFCfg = Cfg.PaperFoldingConfig
        local function rarityColor(r)
            local c = PFCfg and type(PFCfg.RarityColor) == "table" and PFCfg.RarityColor[r]
            if typeof(c) == "Color3" then return c end
            return RCOL[r]
        end
        local function esc(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
        local function hex(c) return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
        local NOTE_W, NOTE_LIFE, NOTE_MAX = 300, 9, 5
        local stack = new("Frame", {
            Name = "DYX_Notifications",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -14, 0, 104),
            Size = UDim2.fromOffset(NOTE_W, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, gui)
        new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
            HorizontalAlignment = Enum.HorizontalAlignment.Right}, stack)
        local noteScale = new("UIScale", {}, stack)
        local function fit()
            local cam = workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
            noteScale.Scale = math.clamp(math.min(vp.Y / 820, vp.X / 1100), 0.62, 1)
        end
        fit()
        if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end

        local seq, live = 0, {}
        local function dismiss(n)
            if n.gone then return end
            n.gone = true
            for i, x in ipairs(live) do if x == n then table.remove(live, i) break end end
            tween(n.card, 0.22, {Position = UDim2.fromOffset(NOTE_W + 40, 0)}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            task.delay(0.24, function() n.holder:Destroy() end)
        end
        function N.push(spec)
            seq += 1
            local accent = spec.ok == false and C.crimson or rarityColor(spec.rarity) or C.emerald
            local holder = new("Frame", {Name = "Note" .. seq, BackgroundTransparency = 1, LayoutOrder = -seq,
                Size = UDim2.fromOffset(NOTE_W, 0), AutomaticSize = Enum.AutomaticSize.Y}, stack)
            -- the card is a button: click to close it early (only fixed/X-scale children, so AutomaticSize Y is stable)
            local card = new("TextButton", {BackgroundColor3 = C.card, BorderSizePixel = 0, BackgroundTransparency = 0.04,
                Text = "", AutoButtonColor = false,
                Position = UDim2.fromOffset(NOTE_W + 40, 0), Size = UDim2.fromOffset(NOTE_W, 0), AutomaticSize = Enum.AutomaticSize.Y}, holder)
            corner(card, 8)
            stroke(card, accent, 1, 0.35)
            local body = new("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y}, card)
            new("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 11)}, body)
            new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3)}, body)
            local order = 0
            new("Frame", {BackgroundColor3 = accent, BorderSizePixel = 0, LayoutOrder = 0, Size = UDim2.new(0, 46, 0, 3)}, body)
            local function text(t, font, size, color, rich)
                order += 1
                return new("TextLabel", {BackgroundTransparency = 1, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = rich == true, Font = font, TextSize = size,
                    TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, Text = t}, body)
            end
            text("◆ " .. tostring(spec.kind or "DYXNET") .. "  ·  " .. os.date("%H:%M:%S"), Enum.Font.GothamBold, 10, C.sub)
            text(tostring(spec.title or ""), Enum.Font.GothamBlack, 16, accent)
            if spec.status then
                text(tostring(spec.status), Enum.Font.GothamBold, 12,
                    spec.ok == false and C.crimson or (spec.ok == true and C.emerald or C.ink))
            end
            order += 1
            new("Frame", {BackgroundColor3 = C.border, BorderSizePixel = 0, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 1)}, body)
            local keyHex = hex(C.sub)
            for _, ln in ipairs(spec.lines or {}) do
                if type(ln) == "table" then
                    text(string.format('<font color="%s">%s</font>   %s', keyHex, esc(ln[1]), esc(ln[2])), Enum.Font.Gotham, 12, C.ink, true)
                elseif ln ~= nil then
                    text(esc(ln), Enum.Font.Gotham, 12, C.ink, true)
                end
            end
            order += 1
            local barBg = new("Frame", {BackgroundColor3 = C.trackOff, BorderSizePixel = 0, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 2)}, body)
            local bar = new("Frame", {BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1)}, barBg)
            local n = {holder = holder, card = card}
            live[#live + 1] = n
            while #live > NOTE_MAX do dismiss(live[1]) end
            card.Activated:Connect(function() dismiss(n) end)
            tween(card, 0.3, {Position = UDim2.fromOffset(0, 0)}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
            tween(bar, NOTE_LIFE, {Size = UDim2.fromScale(0, 1)}, Enum.EasingStyle.Linear)
            task.delay(NOTE_LIFE, function() dismiss(n) end)
        end
    end

    local isMobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
    local PANEL_W, PANEL_H = 560, 392
    local panel = new("Frame", {
        Name = "MainPanel",
        AnchorPoint = isMobile and Vector2.new(0.5, 0.5) or Vector2.new(0, 0),
        Size = UDim2.fromOffset(PANEL_W, PANEL_H),
        Position = isMobile and UDim2.fromScale(0.5, 0.5) or UDim2.new(0, 16, 0.13, 0),
        BackgroundColor3 = C.bg,
        BorderSizePixel = 0,
        Active = true,
        ClipsDescendants = true,
    }, gui)
    corner(panel, 10)
    stroke(panel, C.border, 1)

    buildGrid(panel, PANEL_W, PANEL_H, 56, C.grid, 0.45, 0)
    addTopLaser(panel, 4)
    addCornerBrackets(panel, 14, 2, C.crimson, 0.25)

    -- ========================================================================
    -- HEADER BAR (Top-Left Cropped Square Logo + Live Telemetry + Controls)
    -- ========================================================================
    local header = new("Frame", {
        Name = "Header",
        Size = UDim2.fromOffset(PANEL_W, 64),
        BackgroundColor3 = C.sidebar,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Active = true,
    }, panel)
    new("Frame", {
        Position = UDim2.fromOffset(0, 63),
        Size = UDim2.fromOffset(PANEL_W, 1),
        BackgroundColor3 = C.border,
        BorderSizePixel = 0,
    }, header)

    UI.logo(header, 10, 9, 46)
    label(header, {Text = "DYXNET", Font = Enum.Font.GothamBlack, TextSize = 16, Position = UDim2.fromOffset(65, 10), Size = UDim2.fromOffset(70, 20)})
    label(header, {Text = "// PAPER.OPS", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.crimson, Position = UDim2.fromOffset(136, 11), Size = UDim2.fromOffset(90, 18)})

    local waveHolder = new("Frame", {
        Position = UDim2.fromOffset(65, 34),
        Size = UDim2.fromOffset(36, 14),
        BackgroundTransparency = 1,
    }, header)
    local bars = {}
    for i = 1, 7 do
        local bar = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset((i - 1) * 5 + 2, 7),
            Size = UDim2.fromOffset(2, 6),
            BackgroundColor3 = C.crimson,
            BorderSizePixel = 0,
        }, waveHolder)
        corner(bar, UDim.new(1, 0))
        bars[i] = bar
    end
    label(header, {Text = "SYS.ONLINE", Font = Enum.Font.GothamBold, TextSize = 9, TextColor3 = C.muted, Position = UDim2.fromOffset(104, 33), Size = UDim2.fromOffset(56, 16)})

    -- Language switch (VI | EN) cleanly integrated into Header next to SYS.ONLINE
    local langBox = new("Frame", {
        BackgroundColor3 = C.card,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(162, 33),
        Size = UDim2.fromOffset(44, 16),
    }, header)
    corner(langBox, 4)
    stroke(langBox, C.borderSoft, 1)
    local langBtns = {}
    for i, code in ipairs({"vi", "en"}) do
        local b = new("TextButton", {
            Text = string.upper(code),
            Font = Enum.Font.GothamBlack,
            TextSize = 8,
            AutoButtonColor = false,
            BackgroundColor3 = C.crimson,
            BackgroundTransparency = 1,
            TextColor3 = C.sub,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(2 + (i - 1) * 20, 2),
            Size = UDim2.fromOffset(18, 12),
        }, langBox)
        corner(b, 3)
        langBtns[code] = b
    end

    local function pill(x, w, iconName, iconCol, titleText)
        local p = new("Frame", {
            BackgroundColor3 = C.card,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(x, 13),
            Size = UDim2.fromOffset(w, 38),
        }, header)
        corner(p, 7)
        stroke(p, C.border, 1)
        UI.icon(p, iconName, 8, 10, 18, iconCol)
        local tLbl = label(p, {
            Text = titleText,
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextColor3 = C.muted,
            Position = UDim2.fromOffset(32, 5),
            Size = UDim2.fromOffset(w - 36, 12),
        })
        local vLbl = label(p, {
            Text = "--",
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = C.ink,
            Position = UDim2.fromOffset(32, 17),
            Size = UDim2.fromOffset(w - 36, 16),
        })
        return vLbl, tLbl
    end
    local coinsLbl, coinsTitleLbl = pill(212, 124, "wallet", C.crimson, tr("TIỀN GAME", "COINS"))
    local powerLbl, powerTitleLbl = pill(342, 136, "train", C.emerald, "POWER · REBIRTH")

    local foldBtn = makeIconButton(header, "minimize", 486, 15, 30, 34, C.card, C.sub, C.cardHover)
    local closeBtn = makeIconButton(header, "close", 520, 15, 30, 34, C.card, C.crimson, C.crimsonDark)

    -- ========================================================================
    -- LEFT TACTICAL SIDEBAR
    -- ========================================================================
    local side = new("Frame", {
        Name = "Sidebar",
        Position = UDim2.fromOffset(10, 72),
        Size = UDim2.fromOffset(148, 282),
        BackgroundColor3 = C.sidebar,
        BorderSizePixel = 0,
    }, panel)
    corner(side, 8)
    stroke(side, C.border, 1)
    local sideTitle = label(side, {
        Text = tr("DANH MỤC MODULE", "CATEGORIES"),
        Font = Enum.Font.GothamBold,
        TextSize = 9,
        TextColor3 = C.muted,
        Position = UDim2.fromOffset(10, 8),
        Size = UDim2.fromOffset(128, 14),
    })

    -- ========================================================================
    -- RIGHT TASK COMMAND DECK
    -- ========================================================================
    local deck = new("Frame", {
        Name = "TaskDeck",
        Position = UDim2.fromOffset(166, 72),
        Size = UDim2.fromOffset(384, 282),
        BackgroundColor3 = C.sidebar,
        BorderSizePixel = 0,
    }, panel)
    corner(deck, 8)
    stroke(deck, C.border, 1)

    local deckHeader = new("Frame", {
        Size = UDim2.fromOffset(384, 32),
        BackgroundTransparency = 1,
    }, deck)
    new("Frame", {
        Position = UDim2.fromOffset(0, 31),
        Size = UDim2.fromOffset(384, 1),
        BackgroundColor3 = C.border,
        BorderSizePixel = 0,
    }, deckHeader)

    local deckTitle = label(deckHeader, {
        Text = "TẤT CẢ TÁC VỤ · ALL MODULES",
        Font = Enum.Font.GothamBlack,
        TextSize = 11,
        TextColor3 = C.ink,
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.fromOffset(248, 31),
    })
    local activeSummaryBadge = new("Frame", {
        Position = UDim2.fromOffset(286, 6),
        Size = UDim2.fromOffset(88, 20),
        BackgroundColor3 = C.card,
        BorderSizePixel = 0,
    }, deckHeader)
    corner(activeSummaryBadge, UDim.new(1, 0))
    local activeSummaryStroke = stroke(activeSummaryBadge, C.border, 1)
    local badge = label(activeSummaryBadge, {
        Text = "0/0 ĐANG BẬT",
        Font = Enum.Font.GothamBold,
        TextSize = 9,
        TextColor3 = C.sub,
        TextXAlignment = Enum.TextXAlignment.Center,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(88, 20),
    })

    local scroll = new("ScrollingFrame", {
        Name = "TaskScroll",
        Position = UDim2.fromOffset(6, 36),
        Size = UDim2.fromOffset(372, 240),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = isMobile and 5 or 3,
        ScrollBarImageColor3 = C.crimson,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, deck)
    new("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, scroll)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 2),
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 1),
        PaddingRight = UDim.new(0, 5),
    }, scroll)

    -- ========================================================================
    -- FOOTER CONSOLE BAR & MOBILE-READY MINIMIZED CHIP
    -- ========================================================================
    local footer = new("Frame", {
        Name = "FooterConsole",
        Position = UDim2.fromOffset(10, 359),
        Size = UDim2.fromOffset(540, 25),
        BackgroundColor3 = C.sidebar,
        BorderSizePixel = 0,
    }, panel)
    corner(footer, 6)
    stroke(footer, C.border, 1)
    UI.icon(footer, "terminal", 8, 5, 15, C.crimson)
    local statusLbl = label(footer, {
        Text = "Sẵn sàng",
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = C.sub,
        Position = UDim2.fromOffset(28, 0),
        Size = UDim2.fromOffset(325, 25),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    local function footHint()
        return isMobile and tr("[KÉO THANH TRÊN] DI CHUYỂN · [–] THU GỌN", "DRAG TO MOVE · [–] MINIMIZE")
            or tr("[R-SHIFT] ẨN/HIỆN · [F8] DỪNG", "[R-SHIFT] SHOW/HIDE · [F8] STOP")
    end
    local footHintLbl = label(footer, {
        Text = footHint(),
        Font = Enum.Font.GothamBold,
        TextSize = 9,
        TextColor3 = C.muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Position = UDim2.fromOffset(355, 0),
        Size = UDim2.fromOffset(177, 25),
    })
    S.onStatus = function(m) statusLbl.Text = m end

    local chip = new("TextButton", {
        Name = "MinimizedChip",
        Text = "",
        AutoButtonColor = false,
        Position = isMobile and UDim2.new(0.5, -126, 0, 8) or UDim2.fromOffset(14, 10),
        Size = UDim2.fromOffset(252, 42),
        BackgroundColor3 = C.bg,
        BorderSizePixel = 0,
        Active = true,
        Visible = false,
    }, gui)
    corner(chip, 9)
    stroke(chip, C.crimson, 1, 0.35)
    UI.logo(chip, 6, 6, 30)
    label(chip, {Text = "DYXNET // PAPER", Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = C.ink, Position = UDim2.fromOffset(42, 5), Size = UDim2.fromOffset(122, 15)})
    local chipSub = label(chip, {Text = "0 TÁC VỤ ĐANG CHẠY", Font = Enum.Font.GothamBold, TextSize = 9, TextColor3 = C.crimson, Position = UDim2.fromOffset(42, 21), Size = UDim2.fromOffset(122, 14)})

    local chipStop = new("TextButton", {
        Name = "QuickStopBtn",
        Text = "",
        AutoButtonColor = false,
        Position = UDim2.fromOffset(166, 7),
        Size = UDim2.fromOffset(54, 28),
        BackgroundColor3 = C.crimsonDark,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, chip)
    corner(chipStop, 6)
    stroke(chipStop, C.crimson, 1, 0.35)
    UI.icon(chipStop, "stop", 6, 7, 14, C.crimson)
    local chipStopLbl = label(chipStop, {Text = tr("DỪNG", "STOP"), Font = Enum.Font.GothamBlack, TextSize = 8, TextColor3 = C.ink, Position = UDim2.fromOffset(22, 0), Size = UDim2.fromOffset(30, 28), ZIndex = 4})
    UI.icon(chip, "restore", 227, 13, 16, C.sub)

    -- ========================================================================
    -- DRAGGING HANDLER (Clamped to Viewport + Tap Callback)
    -- ========================================================================
    local function draggable(handle, targetFrame, onTapCallback)
        local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
        local moved = false
        on(handle.InputBegan, function(inp)
            if dragging then return end
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                moved = false
                dragInput = inp
                dragStart = inp.Position
                startPos = targetFrame.Position
            end
        end)
        on(UIS.InputChanged, function(inp)
            if dragging and (inp == dragInput or (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and inp.UserInputType == Enum.UserInputType.MouseMovement)) then
                local delta = inp.Position - dragStart
                if delta.Magnitude > 6 then moved = true end
                local cam = workspace.CurrentCamera
                local vx = cam and cam.ViewportSize.X or 1280
                local vy = cam and cam.ViewportSize.Y or 720
                local newX = startPos.X.Scale * vx + startPos.X.Offset + delta.X
                local newY = startPos.Y.Scale * vy + startPos.Y.Offset + delta.Y
                local fw = targetFrame.AbsoluteSize.X
                local fh = targetFrame.AbsoluteSize.Y
                local ax = targetFrame.AnchorPoint.X
                local ay = targetFrame.AnchorPoint.Y
                local minX = fw * ax + 4
                local maxX = math.max(minX, vx - fw * (1 - ax) - 4)
                local minY = fh * ay + 4
                local maxY = math.max(minY, vy - fh * (1 - ay) - 4)
                targetFrame.Position = UDim2.fromOffset(
                    math.clamp(newX, minX, maxX),
                    math.clamp(newY, minY, maxY)
                )
            end
        end)
        on(UIS.InputEnded, function(inp)
            if inp == dragInput then
                if dragging and not moved and type(onTapCallback) == "function" then
                    onTapCallback()
                end
                dragging = false
                dragInput = nil
            end
        end)
    end
    draggable(header, panel)

    -- ========================================================================
    -- MODULE FOLDERS & TASK DEFINITIONS
    -- ========================================================================
    UI.FOLDERS = {
        {id = "All",     label = "Tất cả tác vụ", labelEn = "All tasks", title = "TẤT CẢ TÁC VỤ · ALL MODULES",   titleEn = "ALL TASKS · ALL MODULES",       icon = "all"},
        {id = "Farm",    label = "Bay & luyện",   labelEn = "Flight",    title = "BAY & LUYỆN · FLIGHT MODULE",   titleEn = "FLIGHT & TRAINING MODULE",      icon = "throw"},
        {id = "Upgrade", label = "Tiến trình",    labelEn = "Upgrades",  title = "TIẾN TRÌNH · UPGRADE MODULE",   titleEn = "PROGRESS · UPGRADE MODULE",     icon = "upgrade"},
        {id = "Rewards", label = "Phần thưởng",   labelEn = "Rewards",   title = "PHẦN THƯỞNG · REWARDS MODULE",  titleEn = "REWARDS MODULE",                icon = "rewards"},
    }
    UI.JOBS = {
        {id = "throw", folder = "Farm", icon = "throw", name = "Auto Fly · SUPER THROW", desc = "Ném 100% Perfect, tự lái né vật cản và lấy ring, ném lại ngay",
            nameEn = "Auto Fly · SUPER THROW", descEn = "100% Perfect throws, auto-dodge obstacles and grab rings, re-throws instantly"},
        {id = "candy", folder = "Farm", icon = "collect", name = "Auto Event · Kẹo Halloween", desc = "Bay như Auto Fly, ưu tiên nhặt kẹo của sự kiện khi đang mưa kẹo",
            nameEn = "Auto Event · Halloween candy", descEn = "Flies like Auto Fly, candy pickups of the event come first"},
        {id = "farm", folder = "Farm", icon = "train", name = "Auto Farm & Rebirth", desc = "Luyện ô tốt nhất tới 100% → Rebirth → lặp lại (không sang world)",
            nameEn = "Auto Farm & Rebirth", descEn = "Train the best zone to 100% → Rebirth → repeat (stays in this world)"},
        {id = "unlock", folder = "Farm", icon = "expand", name = "Auto Unlock World", desc = "Luyện ô tốt nhất → Rebirth đủ yêu cầu → bay tới cổng đích → sang world mới",
            nameEn = "Auto Unlock World", descEn = "Train best zone → Rebirths to requirement → fly to the finish gate → next world"},
        {id = "buyPaper", folder = "Upgrade", icon = "seed", name = "Mua giấy · Paper Shop", desc = "Mua giấy còn hàng từ hiếm nhất tới thường bằng Coins",
            nameEn = "Buy paper · Paper Shop", descEn = "Buys in-stock paper, rarest first, with Coins"},
        {id = "fold", folder = "Upgrade", icon = "collect", name = "Tự gấp máy bay", desc = "Gấp giấy hiếm nhất, canh Perfect từng bước",
            nameEn = "Auto fold planes", descEn = "Folds the rarest paper, Perfect on every step"},
        {id = "fuse", folder = "Upgrade", icon = "bolt", name = "Auto Plane Fuse", desc = "Fuse vào máy bay mạnh nhất bằng máy bay yếu hơn",
            nameEn = "Auto Plane Fuse", descEn = "Fuses weaker planes into your strongest plane"},
        {id = "equip", folder = "Upgrade", icon = "player", name = "Trang bị máy bay mạnh nhất", desc = "Tự đổi sang máy bay mạnh nhất trong kho",
            nameEn = "Equip strongest plane", descEn = "Switches to the strongest plane in your inventory"},
        {id = "playtime", folder = "Rewards", icon = "rewards", name = "Quà theo giờ chơi", desc = "Tự nhận mốc quà Playtime khi sẵn sàng",
            nameEn = "Playtime rewards", descEn = "Claims Playtime rewards when ready"},
        {id = "daily", folder = "Rewards", icon = "daily", name = "Quà hằng ngày", desc = "Tự điểm danh nhận quà Daily",
            nameEn = "Daily reward", descEn = "Claims the Daily reward"},
        {id = "codes", folder = "Rewards", icon = "key", name = "Nhập toàn bộ code", desc = "Bấm CHẠY: thử mọi code một lượt rồi dừng", action = true,
            nameEn = "Redeem all codes", descEn = "Press RUN: tries every code once, then stops"},
        {id = "event", folder = "Rewards", icon = "collect", name = "Đổi kẹo Halloween", desc = "Đổi Candy lấy giấy Mythical/Epic, potion khi đủ",
            nameEn = "Halloween candy exchange", descEn = "Trades Candy for Mythical/Epic paper and potions"},
        {id = "community", folder = "Rewards", icon = "player", name = "Quà cộng đồng", desc = "Nhận rương cộng đồng nếu đã vào group",
            nameEn = "Community chest", descEn = "Claims the community chest if you are in the group"},
    }
    local function jName(j) return tr(j.name, j.nameEn or j.name) end
    local function jDesc(j) return tr(j.desc, j.descEn or j.desc) end

    local function rarityOptions()
        local out = {}
        for i = #RARITIES, 1, -1 do out[#out + 1] = {id = RARITIES[i], label = RARITIES[i] .. " Paper"} end
        return out
    end
    UI.PICKS = {
        buyPaper = {mode = "multi", title = "GIẤY TỰ MUA", titleEn = "PAPER TO BUY", options = rarityOptions},
        fold = {mode = "multi", title = "GIẤY TỰ GẤP", titleEn = "PAPER TO FOLD", options = rarityOptions},
        fuse = {mode = "single", title = "MÁY BAY NÂNG CẤP (còn lại làm nguyên liệu)", titleEn = "PLANE TO UPGRADE (others become materials)", options = function()
            G.refreshProfile()
            local list = {}
            for _, p in ipairs((S.profile and S.profile.Planes) or {}) do list[#list + 1] = p end
            table.sort(list, function(a, b) return G.planeScore(a) > G.planeScore(b) end)
            local out = {{id = "auto", label = tr("Tự động · máy bay mạnh nhất", "Auto · strongest plane")}}
            for _, p in ipairs(list) do out[#out + 1] = {id = p.Uid, label = G.planeLabel(p)} end
            return out
        end},
        event = {mode = "multi", title = "MÓN ĐỔI KẸO (trống = tất cả)", titleEn = "CANDY ITEMS (none = all)", options = function()
            local ev = RS:FindFirstChild("HalloweenEvent")
            local er = ev and ev:FindFirstChild("ExchangeRequest")
            local out = {}
            local ok, st = pcall(function() return er.InvokeServer(er, "State") end)
            if ok and type(st) == "table" then
                for _, it in ipairs(st.List or {}) do
                    out[#out + 1] = {id = tostring(it.Id), label = string.format("%s · %s %s%s", tostring(it.Name or it.Id),
                        tostring(it.Price), tr("kẹo", "candy"), it.Left ~= nil and (tr(" · còn ", " · left ") .. tostring(it.Left)) or "")}
                end
            end
            return out
        end},
        unlock = {mode = "single", title = "Ô LUYỆN LỰC", titleEn = "TRAINING ZONE", options = function() return T.zoneOptions() end},
        farm = {mode = "single", title = "Ô LUYỆN LỰC", titleEn = "TRAINING ZONE", options = function() return T.zoneOptions() end},
    }
    function UI.pickSummary(id)
        local spec, v = UI.PICKS[id], S.opt[id]
        if spec.mode == "single" then return (v == "auto" or v == nil) and "AUTO" or tr("ĐÃ CHỌN", "SET") end
        local n = 0
        for _ in pairs(v or {}) do n += 1 end
        if id == "event" and n == 0 then return tr("TẤT CẢ", "ALL") end
        return n .. tr(" MỤC", " ITEMS")
    end

    UI.rows, UI.tabs, UI.current = {}, {}, "All"
    local deckHeaderIcons = {}
    for _, meta in ipairs(UI.FOLDERS) do
        local ic = UI.icon(deckHeader, meta.icon, 10, 8, 16, C.crimson)
        ic.frame.Visible = (meta.id == "All")
        deckHeaderIcons[meta.id] = ic
    end

    function UI.paint(row, onState, msg)
        onState = (onState == true)
        local hasDetail = msg ~= nil and msg ~= ""
        local nextText = hasDetail and msg or (onState and tr("Đang chạy…", "Running…") or jDesc(row.job))
        local nextDetailCol = (hasDetail or onState) and C.crimsonSoft or C.muted
        if row.sub.Text ~= nextText then row.sub.Text = nextText end
        if row.sub.TextColor3 ~= nextDetailCol then row.sub.TextColor3 = nextDetailCol end

        if row.lastOn == onState then return end
        local firstPaint = (row.lastOn == nil)
        row.lastOn = onState
        row.btn:SetAttribute("FarmSwitchOn", onState)
        row.bar.Visible = onState
        row.tag.Text = onState and "ON" or "OFF"
        row.tag.TextColor3 = onState and C.crimson or C.muted
        row.cardStroke.Color = onState and C.crimson or C.border
        row.cardStroke.Transparency = onState and 0.45 or 0
        row.iconBox.BackgroundColor3 = onState and C.crimsonDark or C.bg
        row.iconStroke.Color = onState and C.crimson or C.borderSoft
        row.iconStroke.Transparency = onState and 0.35 or 0
        row.iconObj.setColor(onState and C.crimson or C.sub)
        row.trackStroke.Color = onState and C.crimson or C.border

        if firstPaint then
            row.card.BackgroundColor3 = onState and C.cardOn or C.card
            row.track.BackgroundColor3 = onState and C.crimson or C.trackOff
            row.knob.Position = UDim2.fromOffset(onState and 21 or 3, 3)
            row.knob.BackgroundColor3 = onState and C.ink or C.sub
        else
            tween(row.card, 0.15, {BackgroundColor3 = onState and C.cardOn or C.card})
            tween(row.track, 0.15, {BackgroundColor3 = onState and C.crimson or C.trackOff})
            tween(row.knob, 0.15, {
                Position = UDim2.fromOffset(onState and 21 or 3, 3),
                BackgroundColor3 = onState and C.ink or C.sub,
            })
        end
    end

    function UI.describe(id, msg)
        local r = UI.rows[id]
        if r then UI.paint(r, S.on[id] == true, msg) end
    end

    function UI.refreshCounts()
        local total, active = 0, 0
        for _, j in ipairs(UI.JOBS) do
            if not j.action and (UI.current == "All" or j.folder == UI.current) then
                total += 1
                if S.on[j.id] then active += 1 end
            end
        end
        badge.Text = active .. "/" .. total .. tr(" ĐANG BẬT", " ACTIVE")
        badge.TextColor3 = active > 0 and C.crimson or C.sub
        activeSummaryStroke.Color = active > 0 and C.crimson or C.border

        local allActive = 0
        for _, j in ipairs(UI.JOBS) do
            if not j.action and S.on[j.id] then allActive += 1 end
        end
        chipSub.Text = allActive .. tr(" TÁC VỤ ĐANG CHẠY", " RUNNING")

        for id, t in pairs(UI.tabs) do
            local n = 0
            for _, j in ipairs(UI.JOBS) do
                if not j.action and (id == "All" or j.folder == id) and S.on[j.id] then n += 1 end
            end
            t.count.Text = tostring(n)
            t.badgeBg.BackgroundColor3 = n > 0 and C.crimson or C.bg
            t.count.TextColor3 = n > 0 and C.ink or C.muted
        end
    end

    -- Auto Unlock World drives the character itself (train -> rebirth -> gate throws), so turning it
    -- on switches off every other task except claiming rewards and buying from the shops.
    local KEEP_WITH_UNLOCK = {unlock = true, playtime = true, daily = true, community = true, buyPaper = true, event = true}
    function UI.set(id, onState)
        S.on[id] = onState and true or false
        local r = UI.rows[id]
        if r then UI.paint(r, S.on[id]) end
        if id == "unlock" and S.on[id] then
            local off = {}
            for _, j in ipairs(UI.JOBS) do
                if not j.action and not KEEP_WITH_UNLOCK[j.id] and S.on[j.id] then
                    S.on[j.id] = false
                    if UI.rows[j.id] then UI.paint(UI.rows[j.id], false) end
                    if S.onToggle then S.onToggle(j.id, false) end
                    off[#off + 1] = j.name
                end
            end
            if #off > 0 then say(tr("Auto Unlock World đã tắt: ", "Auto Unlock World turned off: ") .. table.concat(off, ", ")) end
        end
        -- both drive the character through training/rebirth: Auto Farm & Rebirth takes over from Auto Unlock World
        if id == "farm" and S.on[id] and S.on.unlock then
            S.on.unlock = false
            if UI.rows.unlock then UI.paint(UI.rows.unlock, false) end
            if S.onToggle then S.onToggle("unlock", false) end
            say(tr("Auto Farm & Rebirth bật → đã tắt Auto Unlock World", "Auto Farm & Rebirth on → Auto Unlock World turned off"))
        end
        UI.refreshCounts()
        if S.onToggle then S.onToggle(id, S.on[id]) end
    end

    -- ========================================================================
    -- CYBER TASK SWITCH ROW BUILDER
    -- ========================================================================
    for i, job in ipairs(UI.JOBS) do
        local card = new("Frame", {
            Name = job.id .. "Card",
            BackgroundColor3 = C.card,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(364, 52),
            LayoutOrder = i * 2,
        }, scroll)
        corner(card, 7)
        local cs = stroke(card, C.border, 1)

        local bar = new("Frame", {
            Position = UDim2.fromOffset(0, 9),
            Size = UDim2.fromOffset(3, 34),
            BackgroundColor3 = C.crimson,
            BorderSizePixel = 0,
            Visible = false,
        }, card)
        corner(bar, UDim.new(1, 0))

        local ib = new("Frame", {
            Position = UDim2.fromOffset(10, 9),
            Size = UDim2.fromOffset(34, 34),
            BackgroundColor3 = C.bg,
            BorderSizePixel = 0,
        }, card)
        corner(ib, 7)
        local is = stroke(ib, C.borderSoft, 1)
        local ic = UI.icon(ib, job.icon, 8, 8, 18, C.sub)

        local textW = UI.PICKS[job.id] and 154 or 226
        local nameLbl = label(card, {
            Text = jName(job),
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = C.ink,
            Position = UDim2.fromOffset(52, 7),
            Size = UDim2.fromOffset(textW, 18),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        local sub = label(card, {
            Text = jDesc(job),
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextColor3 = C.muted,
            Position = UDim2.fromOffset(52, 26),
            Size = UDim2.fromOffset(textW, 18),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        local tag = label(card, {
            Text = "OFF",
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextColor3 = C.muted,
            TextXAlignment = Enum.TextXAlignment.Right,
            Position = UDim2.fromOffset(280, 16),
            Size = UDim2.fromOffset(30, 20),
        })

        local track = new("Frame", {
            Name = "Track",
            Position = UDim2.fromOffset(316, 16),
            Size = UDim2.fromOffset(38, 20),
            BackgroundColor3 = C.trackOff,
            BorderSizePixel = 0,
        }, card)
        corner(track, UDim.new(1, 0))
        local ts = stroke(track, C.border, 1)

        local knob = new("Frame", {
            Name = "Knob",
            Position = UDim2.fromOffset(3, 3),
            Size = UDim2.fromOffset(14, 14),
            BackgroundColor3 = C.sub,
            BorderSizePixel = 0,
        }, track)
        corner(knob, UDim.new(1, 0))

        local btn = new("TextButton", {
            Name = job.id,
            Text = "",
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
        }, card)

        local row = {
            job = job, card = card, cardStroke = cs, bar = bar,
            iconBox = ib, iconStroke = is, iconObj = ic,
            nameLbl = nameLbl, sub = sub, tag = tag,
            track = track, trackStroke = ts, knob = knob, btn = btn,
        }
        UI.rows[job.id] = row

        if UI.PICKS[job.id] then
            local pb = new("TextButton", {
                Text = "",
                AutoButtonColor = false,
                BackgroundColor3 = C.crimsonDark,
                BorderSizePixel = 0,
                ZIndex = 5,
                Position = UDim2.fromOffset(210, 15),
                Size = UDim2.fromOffset(64, 22),
            }, card)
            corner(pb, 5)
            local pbStroke = stroke(pb, C.crimson, 1, 0.35)
            row.pickLbl = label(pb, {
                Text = UI.pickSummary(job.id),
                Font = Enum.Font.GothamBold,
                TextSize = 9,
                TextColor3 = C.crimsonSoft,
                ZIndex = 6,
                TextXAlignment = Enum.TextXAlignment.Center,
                Size = UDim2.fromScale(1, 1),
            })
            on(pb.MouseEnter, function() pbStroke.Transparency = 0 end)
            on(pb.MouseLeave, function() pbStroke.Transparency = 0.35 end)
            pb.Activated:Connect(function() UI.openPick(job.id) end)

            local exp = new("Frame", {
                BackgroundColor3 = C.sidebar,
                BorderSizePixel = 0,
                Size = UDim2.fromOffset(364, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = i * 2 + 1,
                Visible = false,
            }, scroll)
            corner(exp, 7)
            stroke(exp, C.crimson, 1, 0.35)
            new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, exp)
            new("UIPadding", {
                PaddingTop = UDim.new(0, 6),
                PaddingBottom = UDim.new(0, 6),
                PaddingLeft = UDim.new(0, 8),
                PaddingRight = UDim.new(0, 8),
            }, exp)
            row.exp = exp
        end

        on(btn.MouseEnter, function()
            tween(card, 0.12, {BackgroundColor3 = S.on[job.id] and C.cardOn or C.cardHover})
        end)
        on(btn.MouseLeave, function()
            tween(card, 0.12, {BackgroundColor3 = S.on[job.id] and C.cardOn or C.card})
        end)

        if job.action then
            track.Visible, tag.Visible = false, false
            local rb = new("TextButton", {
                Text = tr("CHẠY", "RUN"),
                Font = Enum.Font.GothamBlack,
                TextSize = 10,
                TextColor3 = C.ink,
                AutoButtonColor = false,
                BackgroundColor3 = C.crimson,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(290, 15),
                Size = UDim2.fromOffset(64, 22),
                ZIndex = 5,
            }, card)
            corner(rb, 5)
            row.runBtn = rb
            local function run() UI.runAction(job) end
            rb.Activated:Connect(run)
            btn.Activated:Connect(run)
        else
            btn.Activated:Connect(function() UI.set(job.id, not S.on[job.id]) end)
        end
        UI.paint(row, false)
    end

    -- ========================================================================
    -- SIDEBAR TABS & QUICK CONTROLS
    -- ========================================================================
    local function openFolder(id)
        UI.current = id
        for _, f in ipairs(UI.FOLDERS) do
            local sel = (f.id == id)
            if deckHeaderIcons[f.id] then
                deckHeaderIcons[f.id].frame.Visible = sel
            end
            if sel then
                deckTitle.Text = tr(f.title, f.titleEn)
            end
        end
        for _, j in ipairs(UI.JOBS) do
            local r = UI.rows[j.id]
            r.card.Visible = (id == "All" or j.folder == id)
            if r.exp then r.exp.Visible = false end
        end
        for tid, t in pairs(UI.tabs) do
            local sel = (tid == id)
            t.bar.Visible = sel
            t.btn.BackgroundColor3 = sel and C.cardOn or C.card
            t.stroke.Color = sel and C.crimson or C.borderSoft
            t.stroke.Transparency = sel and 0.35 or 0
            t.text.TextColor3 = sel and C.ink or C.sub
            t.icon.setColor(sel and C.crimson or C.sub)
        end
        UI.refreshCounts()
    end

    for i, f in ipairs(UI.FOLDERS) do
        local b = new("TextButton", {
            Name = f.id .. "Tab",
            Text = "",
            AutoButtonColor = false,
            BackgroundColor3 = C.card,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(6, 25 + (i - 1) * 35),
            Size = UDim2.fromOffset(136, 31),
        }, side)
        corner(b, 6)
        local st = stroke(b, C.borderSoft, 1)
        local bar = new("Frame", {
            Position = UDim2.fromOffset(0, 6),
            Size = UDim2.fromOffset(3, 19),
            BackgroundColor3 = C.crimson,
            BorderSizePixel = 0,
            Visible = false,
        }, b)
        corner(bar, UDim.new(1, 0))
        local ic = UI.icon(b, f.icon, 9, 7, 17, C.sub)
        local tx = label(b, {
            Text = tr(f.label, f.labelEn),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = C.sub,
            Position = UDim2.fromOffset(32, 0),
            Size = UDim2.fromOffset(72, 31),
        })
        local badgeBg = new("Frame", {
            Position = UDim2.fromOffset(105, 7),
            Size = UDim2.fromOffset(25, 17),
            BackgroundColor3 = C.bg,
            BorderSizePixel = 0,
        }, b)
        corner(badgeBg, UDim.new(1, 0))
        local cnt = label(badgeBg, {
            Text = "0",
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextColor3 = C.muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromOffset(25, 17),
        })
        UI.tabs[f.id] = {btn = b, stroke = st, bar = bar, icon = ic, text = tx, badgeBg = badgeBg, count = cnt}
        b.Activated:Connect(function() openFolder(f.id) end)
    end

    new("Frame", {
        Position = UDim2.fromOffset(10, 204),
        Size = UDim2.fromOffset(128, 1),
        BackgroundColor3 = C.border,
        BorderSizePixel = 0,
    }, side)

    local preset = new("TextButton", {
        Name = "PresetAFK",
        Text = "",
        AutoButtonColor = false,
        Position = UDim2.fromOffset(6, 211),
        Size = UDim2.fromOffset(136, 31),
        BackgroundColor3 = C.crimson,
        BorderSizePixel = 0,
    }, side)
    corner(preset, 6)
    UI.icon(preset, "bolt", 10, 7, 17, C.ink)
    local presetLbl = label(preset, {
        Text = tr("TREO MÁY AUTO", "AFK AUTO MODE"),
        Font = Enum.Font.GothamBlack,
        TextSize = 11,
        TextColor3 = C.ink,
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.fromOffset(100, 31),
    })

    local stopBtn = new("TextButton", {
        Name = "StopAll",
        Text = "",
        AutoButtonColor = false,
        Position = UDim2.fromOffset(6, 246),
        Size = UDim2.fromOffset(136, 30),
        BackgroundColor3 = C.crimsonDark,
        BorderSizePixel = 0,
    }, side)
    corner(stopBtn, 6)
    stroke(stopBtn, C.crimson, 1, 0.4)
    UI.icon(stopBtn, "stop", 10, 7, 16, C.crimson)
    local stopLbl = label(stopBtn, {
        Text = isMobile and tr("DỪNG TẤT CẢ", "STOP ALL") or tr("DỪNG TẤT CẢ · F8", "STOP ALL · F8"),
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = C.ink,
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.fromOffset(100, 30),
    })

    function UI.stopAll()
        for _, j in ipairs(UI.JOBS) do if S.on[j.id] then UI.set(j.id, false) end end
        say(tr("Đã dừng tất cả", "All tasks stopped"))
    end
    UI.running = {}
    function UI.runAction(job)
        if UI.running[job.id] then return end
        UI.running[job.id] = true
        local row = UI.rows[job.id]
        row.runBtn.Text, row.runBtn.BackgroundColor3 = "…", C.crimsonDark
        UI.paint(row, false, tr("Đang chạy…", "Running…"))
        row.sub.TextColor3 = C.crimsonSoft
        task.spawn(function()
            local ok, res = pcall(UI.ACTIONS[job.id])
            UI.running[job.id] = nil
            row.runBtn.Text, row.runBtn.BackgroundColor3 = tr("CHẠY", "RUN"), C.crimson
            UI.paint(row, false, ok and tostring(res) or (tr("Lỗi: ", "Error: ") .. tostring(res)))
        end)
    end
    UI.ACTIONS = {
        codes = function()
            local n, tried = W.codes()
            return string.format(tr("Xong · nhận %d code mới · đã thử %d code", "Done · %d new codes redeemed · %d tried"), n, tried or 0)
        end,
    }
    preset.Activated:Connect(function()
        for _, j in ipairs(UI.JOBS) do if not j.action and not S.on[j.id] then UI.set(j.id, true) end end
        say(tr("TREO MÁY: bật toàn bộ tác vụ", "AFK MODE: every task enabled"))
    end)

    function UI.applyLang()
        for code, b in pairs(langBtns) do
            local sel = S.opt.lang == code
            b.BackgroundTransparency = sel and 0 or 1
            b.TextColor3 = sel and C.ink or C.sub
        end
        coinsTitleLbl.Text = tr("TIỀN GAME", "COINS")
        sideTitle.Text = tr("DANH MỤC MODULE", "CATEGORIES")
        footHintLbl.Text = footHint()
        presetLbl.Text = tr("TREO MÁY AUTO", "AFK AUTO MODE")
        stopLbl.Text = isMobile and tr("DỪNG TẤT CẢ", "STOP ALL") or tr("DỪNG TẤT CẢ · F8", "STOP ALL · F8")
        chipStopLbl.Text = tr("DỪNG", "STOP")
        for _, f in ipairs(UI.FOLDERS) do UI.tabs[f.id].text.Text = tr(f.label, f.labelEn) end
        for _, j in ipairs(UI.JOBS) do
            local r = UI.rows[j.id]
            r.nameLbl.Text = jName(j)
            if r.pickLbl then r.pickLbl.Text = UI.pickSummary(j.id) end
            if r.runBtn and not UI.running[j.id] then r.runBtn.Text = tr("CHẠY", "RUN") end
            if not (r.runBtn and UI.running[j.id]) then
                r.sub.Text = S.on[j.id] and tr("Đang chạy…", "Running…") or jDesc(j)
            end
            if r.exp and r.exp.Visible then r.exp.Visible = false UI.openPick(j.id) end
        end
        openFolder(UI.current)
    end
    for code, b in pairs(langBtns) do
        b.Activated:Connect(function()
            if S.opt.lang == code then return end
            S.opt.lang = code
            saveOpt()
            UI.applyLang()
        end)
    end

    local function collapse(v)
        panel.Visible = not v
        chip.Visible = v
    end
    stopBtn.Activated:Connect(UI.stopAll)
    chipStop.Activated:Connect(function()
        UI.stopAll()
        collapse(false)
    end)
    foldBtn.Activated:Connect(function() collapse(true) end)
    draggable(chip, chip, function() collapse(false) end)
    closeBtn.Activated:Connect(function() if env.DYX_PaperOps_Close then env.DYX_PaperOps_Close() end end)
    on(UIS.InputBegan, function(i, gp)
        if gp then return end
        if i.KeyCode == Enum.KeyCode.F8 then UI.stopAll()
        elseif i.KeyCode == Enum.KeyCode.RightShift then collapse(panel.Visible) end
    end)

    -- ========================================================================
    -- INLINE ACCORDION DROPDOWN PICKER
    -- ========================================================================
    local optionsCache = {}
    local function selected(id, key)
        local v = S.opt[id]
        if UI.PICKS[id].mode == "single" then return tostring(v) == tostring(key) end
        return type(v) == "table" and v[tostring(key)] == true
    end
    local renderExp
    local function choose(id, key, disabled)
        if disabled then return end
        local spec = UI.PICKS[id]
        if spec.mode == "single" then
            S.opt[id] = key
        else
            S.opt[id] = type(S.opt[id]) == "table" and S.opt[id] or {}
            local k = tostring(key)
            S.opt[id][k] = (not S.opt[id][k]) or nil
        end
        saveOpt()
        UI.rows[id].pickLbl.Text = UI.pickSummary(id)
        renderExp(id, optionsCache[id] or {}, nil)
    end
    renderExp = function(id, options, hint)
        local row, spec = UI.rows[id], UI.PICKS[id]
        local exp = row.exp
        for _, c in ipairs(exp:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
        local head = new("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(348, 22), LayoutOrder = 0}, exp)
        label(head, {
            Text = tr(spec.title, spec.titleEn or spec.title),
            Font = Enum.Font.GothamBlack,
            TextSize = 9,
            TextColor3 = C.crimsonSoft,
            Size = UDim2.fromOffset(spec.mode == "multi" and 190 or 348, 22),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        if spec.mode == "multi" then
            local function hb(x, text, fn)
                local b = new("TextButton", {
                    Text = text,
                    Font = Enum.Font.GothamBold,
                    TextSize = 9,
                    TextColor3 = C.ink,
                    AutoButtonColor = false,
                    BackgroundColor3 = C.card,
                    BorderSizePixel = 0,
                    Position = UDim2.fromOffset(x, 1),
                    Size = UDim2.fromOffset(74, 20),
                }, head)
                corner(b, 5)
                stroke(b, C.borderSoft, 1)
                b.Activated:Connect(fn)
            end
            hb(196, tr("CHỌN HẾT", "SELECT ALL"), function()
                S.opt[id] = {}
                for _, o in ipairs(optionsCache[id] or {}) do if not o.disabled then S.opt[id][tostring(o.id)] = true end end
                saveOpt() row.pickLbl.Text = UI.pickSummary(id) renderExp(id, optionsCache[id] or {}, nil)
            end)
            hb(274, tr("BỎ HẾT", "CLEAR"), function()
                S.opt[id] = {} saveOpt() row.pickLbl.Text = UI.pickSummary(id) renderExp(id, optionsCache[id] or {}, nil)
            end)
        end
        if hint or #options == 0 then
            label(exp, {
                Text = hint or tr("Không có mục nào", "Nothing to choose"),
                Font = Enum.Font.GothamMedium,
                TextSize = 10,
                TextColor3 = C.muted,
                Size = UDim2.fromOffset(348, 22),
                LayoutOrder = 1,
            })
        end
        for i, o in ipairs(options) do
            local sel = selected(id, o.id)
            local b = new("TextButton", {
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = 1 + i,
                BackgroundColor3 = sel and C.cardOn or C.card,
                BorderSizePixel = 0,
                Size = UDim2.fromOffset(348, 26),
            }, exp)
            corner(b, 5)
            stroke(b, sel and C.crimson or C.borderSoft, 1, sel and 0.35 or 0)
            local box = new("Frame", {
                BackgroundColor3 = sel and C.crimson or C.trackOff,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(8, 6),
                Size = UDim2.fromOffset(14, 14),
            }, b)
            corner(box, spec.mode == "single" and UDim.new(1, 0) or 3)
            label(b, {
                Text = o.label,
                Font = sel and Enum.Font.GothamBold or Enum.Font.GothamMedium,
                TextSize = 10,
                TextColor3 = o.disabled and C.muted or (sel and C.ink or C.sub),
                Position = UDim2.fromOffset(30, 0),
                Size = UDim2.fromOffset(312, 26),
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            b.Activated:Connect(function() choose(id, o.id, o.disabled) end)
        end
    end
    function UI.openPick(id)
        local row = UI.rows[id]
        if row.exp.Visible then row.exp.Visible = false return end
        for _, r in pairs(UI.rows) do if r.exp then r.exp.Visible = false end end
        row.exp.Visible = true
        renderExp(id, optionsCache[id] or {}, tr("Đang tải danh sách…", "Loading…"))
        task.spawn(function()
            local ok, list = pcall(UI.PICKS[id].options)
            optionsCache[id] = ok and list or {}
            if row.exp.Visible then renderExp(id, optionsCache[id], nil) end
        end)
    end

    -- ========================================================================
    -- VIEWPORT AUTO-SCALE + BOTTOM-RIGHT RESIZE GRIP
    -- ========================================================================
    local scale = new("UIScale", {}, panel)
    local chipScale = new("UIScale", {}, chip)
    local userScale = math.max(1, tonumber(S.opt.uiScale) or 1)
    local function baseFit()
        local cam = workspace.CurrentCamera
        local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
        return math.clamp(math.min(1, (v.Y * 0.88) / PANEL_H, (v.X - 28) / PANEL_W), 0.48, 1), v
    end
    local function maxUser()
        local b, v = baseFit()
        return math.max(1, math.min((v.Y * 0.96) / PANEL_H, (v.X - 16) / PANEL_W) / b)
    end
    local function fit()
        local b, v = baseFit()
        userScale = math.clamp(userScale, 1, maxUser())
        scale.Scale = b * userScale
        chipScale.Scale = math.clamp(math.min(1, (v.X - 20) / 268), 0.72, 1)
    end
    fit()
    if workspace.CurrentCamera then
        on(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), fit)
    end

    local grip = new("TextButton", {
        Text = "",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        ZIndex = 10,
        Position = UDim2.fromOffset(538, 370),
        Size = UDim2.fromOffset(22, 22),
    }, panel)
    for k = 0, 2 do
        new("Frame", {
            BorderSizePixel = 0,
            BackgroundColor3 = C.crimson,
            ZIndex = 10,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Rotation = -45,
            Position = UDim2.fromOffset(13 + k * 3, 13 + k * 3),
            Size = UDim2.fromOffset(12 - k * 4, 2),
        }, grip)
    end
    local resizing, rStart, rScale, rInput
    grip.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            resizing, rStart, rScale, rInput = true, i.Position, userScale, i
        end
    end)
    on(UIS.InputChanged, function(i)
        if not resizing then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement and i ~= rInput then return end
        local d = i.Position - rStart
        local b = baseFit()
        userScale = math.clamp(rScale + math.max(d.X / (PANEL_W * b * rScale), d.Y / (PANEL_H * b * rScale)) * rScale, 1, maxUser())
        scale.Scale = b * userScale
    end)
    on(UIS.InputEnded, function(i)
        if resizing and (i == rInput or i.UserInputType == Enum.UserInputType.MouseButton1) then
            resizing = false
            S.opt.uiScale = userScale
            saveOpt()
        end
    end)

    UI.applyLang()
    openFolder("All")

    -- Throttled Equalizer Pulse (20 FPS + pixel-height diff check)
    local acc, heights = 0, {}
    on(Run.RenderStepped, function(dt)
        acc += (dt or 0.016)
        if acc < 0.045 or not panel.Visible then return end
        acc = 0
        local t = os.clock()
        for i, b in ipairs(bars) do
            local h = math.floor(3 + 9 * (0.5 + 0.5 * math.sin(i * 0.95 + t * 4.2)) + 0.5)
            if heights[i] ~= h then
                heights[i] = h
                b.Size = UDim2.fromOffset(2, h)
            end
        end
    end)

    task.spawn(function()
        while S.alive do
            coinsLbl.Text = "$" .. G.abbrev(G.coins())
            local ls = lp:FindFirstChild("leaderstats")
            powerLbl.Text = G.abbrev(lp:GetAttribute("TrainingPower")) .. " · R" .. tostring(ls and ls:FindFirstChild("Rebirths") and ls.Rebirths.Value or 0)
            task.wait(1)
        end
    end)
end

-- ============================================================ SCHEDULER
do
    local trainTurn = false
    local function anyOn(...) for _, k in ipairs({...}) do if S.on[k] then return true end end return false end
    S.onToggle = function(id, v)
        if id == "throw" or id == "train" or id == "candy" then S.token += 1 end
    end
    -- character owner loop
    task.spawn(function()
        while S.alive do
            local token = S.token
            local did = false
            local ok, err = pcall(function()
                if S.gateLocked then return end
                if not F.idle() then
                    -- our plane is in the air: the server pins the character at the launch zone (teleports, shop,
                    -- training are refused), so just let the Heartbeat steering fly it
                    if U.due("flystat", 10) then say(F.status() or "") end
                    return
                end
                -- plane is home: character jobs in priority order, then the unlock planner, then farming throws
                if S.on.unlock and U.due("world", 10) and U.world(token) then
                    S.gateTries, S.gateCrashes, S.gatePending, S.gateMode = 0, 0, nil, false
                    did = true return
                end
                if S.on.fold and U.due("fold", 20) and U.fold(token) then U.next.fold = 0 did = true return end
                if S.on.fuse and U.due("fuse", 45) and U.fuse() then did = true return end
                if S.on.buyPaper and U.due("buyPaper", 60) and U.buyPaper() then did = true return end
                if S.on.equip and U.due("equip", 90) then U.equipBest() end
                if S.on.event and U.due("event", 90) and U.exchange() then did = true return end
                if S.on.unlock then
                    -- AUTO UNLOCK WORLD
                    --  A) rebirths below the gate requirement: train to 100%, then rebirth
                    --  B) requirement met: train until Power >= the world's Finish Power, then throw at the gate (no rebirth)
                    --     fallback: 4 gate throws without unlocking -> one rebirth (if allowed) for a stronger multiplier
                    local req = U.gateReq()
                    local full = lp:GetAttribute("CanRebirth") == true
                    if U.due("unlockstat", 20) then
                        local step = not req.met and tr("cần thêm Rebirth", "need more Rebirths")
                            or (req.strong and tr("bay tới cổng đích", "flying for the finish gate") or tr("luyện tới Finish Power", "training to Finish Power"))
                        say(string.format(tr("Mở world %d: Rebirth %d/%d · Power %s/%s · %s", "Unlock world %d: Rebirth %d/%d · Power %s/%s · %s"),
                            req.world + 1, req.have, req.need, G.abbrev(req.power), G.abbrev(req.finish), step))
                    end
                    if req.lastWorld then
                        -- final world: nothing left to unlock, keep growing
                        if full then U.rebirth() did = true return end
                    elseif not req.met then
                        if full then
                            say(tr("Chưa đủ Rebirth cho cổng — REBIRTH", "Not enough Rebirths for the gate — REBIRTH"))
                            U.rebirth() did = true return
                        end
                    elseif req.strong then
                        -- score the previous gate flight: only a clean landing short of the gate means "not enough power".
                        -- A crash says nothing about power, and a rebirth would throw away the whole Finish Power.
                        if S.gatePending and F.landing and F.landing.at >= S.gatePending then
                            S.gatePending = nil
                            if F.landing.reason == "Crash" then
                                S.gateCrashes = (S.gateCrashes or 0) + 1
                                say(string.format(tr("Lượt tới cổng bị va chạm ở %d studs — ném lại (giữ nguyên Power)", "Gate run crashed at %d studs — throwing again (Power kept)"), math.floor(F.landing.distance)))
                            elseif F.landing.reason ~= "Hit" then
                                S.gateTries = (S.gateTries or 0) + 1
                                say(string.format(tr("Hạ cánh %d studs, chưa tới cổng (%d/3)", "Landed at %d studs, short of the gate (%d/3)"), math.floor(F.landing.distance), S.gateTries))
                            end
                        end
                        if (S.gateTries or 0) >= 3 then
                            S.gateTries = 0
                            if full then
                                say(tr("3 lần hạ cánh trước cổng — REBIRTH để mạnh hơn", "3 clean landings short of the gate — REBIRTH for more power"))
                                U.rebirth() did = true return
                            end
                            say(tr("3 lần hạ cánh trước cổng — luyện thêm 90 giây", "3 clean landings short of the gate — training 90 s more"))
                            S.forceTrainUntil = now() + 90
                            T.session(token, 90)
                            did = true return
                        end
                        S.gateMode = true
                        say(string.format(tr("Ném tới cổng đích · thiếu lực %d/3 · va chạm %d", "Throwing for the finish gate · short %d/3 · crashes %d"), S.gateTries or 0, S.gateCrashes or 0))
                        did = F.throwOnce(token)
                        if did then S.gatePending = now() else task.wait(2) end
                        return
                    end
                    S.gateMode = false
                    -- not at 100% yet: train (short slices between farming throws, long otherwise)
                    if not (S.on.throw or S.on.candy) or S.trainedForFlight ~= S.stats.throws then
                        S.trainedForFlight = S.stats.throws
                        T.session(token, (S.on.throw or S.on.candy) and (tonumber(S.opt.trainSlice) or 30) or 120)
                        did = true return
                    end
                end
                if S.on.farm and not S.on.unlock then
                    -- AUTO FARM & REBIRTH: train the best (or chosen) zone to 100% → REBIRTH → repeat.
                    -- Never travels or flies to the gate. With Auto Fly on, training slices alternate with throws.
                    if lp:GetAttribute("CanRebirth") == true and lp:GetAttribute("RebirthCapped") ~= true then
                        if U.rebirth() then S.stats.rebirths = (S.stats.rebirths or 0) + 1 end
                        did = true return
                    end
                    if not (S.on.throw or S.on.candy) or S.trainedForFlight ~= S.stats.throws then
                        S.trainedForFlight = S.stats.throws
                        T.session(token, (S.on.throw or S.on.candy) and (tonumber(S.opt.trainSlice) or 30) or 120)
                        did = true return
                    end
                end
                if (S.on.throw or S.on.candy) then
                    if not S.on.unlock then S.gateMode = false end
                    if S.on.candy and U.due("candystat", 60) then
                        say(F.candyActive() and tr("Đang mưa kẹo — ưu tiên nhặt kẹo khi bay", "Candy weather is on — candy comes first in flight")
                            or tr("Chưa có mưa kẹo — bay lấy ring, tự nhặt kẹo khi sự kiện bắt đầu", "No candy weather right now — flying for rings, candy is picked up as soon as it starts"))
                    end
                    did = F.throwOnce(token)
                    if not did then task.wait(2) end
                    return
                end
            end)
            if not ok then say("Lỗi: " .. tostring(err)) task.wait(2) end
            if not did then
                if F.idle() then F.patch(false) end      -- keep the dodge patch while a flight is in the air
                task.wait(0.5)
            end
        end
    end)
    -- reward loops: one independent loop each, so a slow task never blocks the others
    local function loop(id, gap, fn)
        task.spawn(function()
            while S.alive do
                if S.on[id] then
                    local ok, err = pcall(fn)
                    if not ok then say(id .. " lỗi: " .. tostring(err)) end
                end
                for _ = 1, gap do if not S.alive then break end task.wait(1) end
            end
        end)
    end
    loop("playtime", 15, W.playtime)
    loop("daily", 60, W.daily)
    loop("community", 120, W.community)
end

-- ============================================================ LIFECYCLE
env.DYX_PaperOps_Close = function()
    local keep = {}
    for k, v in pairs(S.on) do if v then keep[k] = true end end
    S.alive = false
    S.token += 1
    pcall(F.restore)
    pcall(function() TrainingRE.FireServer(TrainingRE, "Exit", S.trainSeq + 1) end)
    for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    if UI.gui then UI.gui:Destroy() end
    pcall(flushLog)
    env.DYX_PaperOps_Close = nil
    return keep
end
for id in pairs(restore) do UI.set(id, true) end
say(tr("DYXNET // PAPER.OPS sẵn sàng · World ", "DYXNET // PAPER.OPS ready · World ") .. G.world())
