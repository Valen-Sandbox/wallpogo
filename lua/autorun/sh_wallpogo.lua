local cvarFlags         = {FCVAR_ARCHIVE + FCVAR_REPLICATED}
local wallPogoEnabled   = CreateConVar("sv_wallpogo_enabled", "1", cvarFlags, "Whether WallPogo should be enabled or not; takes a value of 0 or 1.", 0, 1):GetBool()
local wallRunSpeedMult  = CreateConVar("sv_wallpogo_wallrun_speedmult", "1", cvarFlags, "Sets the multiplier for wallrun speed.", 0):GetFloat()
local wallJumpSideMult  = CreateConVar("sv_wallpogo_walljump_sidemult", "1", cvarFlags, "Sets the multiplier for horizontal walljump speed.", 0):GetFloat()
local wallJumpVertMult  = CreateConVar("sv_wallpogo_walljump_vertmult", "1", cvarFlags, "Sets the multiplier for vertical walljump speed.", 0):GetFloat()

cvars.AddChangeCallback("sv_wallpogo_enabled", function(_, _, newVal)
    wallPogoEnabled = tobool(newVal)
end, "WallPogo_Enabled")
cvars.AddChangeCallback("sv_wallpogo_wallrun_speedmult", function(_, _, newVal)
    wallRunSpeedMult = tonumber(newVal) or 1
end, "WallPogo_WallRun_SpeedMult")
cvars.AddChangeCallback("sv_wallpogo_walljump_sidemult", function(_, _, newVal)
    wallJumpSideMult = tonumber(newVal) or 1
end, "WallPogo_WallJump_SideMult")
cvars.AddChangeCallback("sv_wallpogo_walljump_vertmult", function(_, _, newVal)
    wallJumpVertMult = tonumber(newVal) or 1
end, "WallPogo_WallJump_VertMult")

local originOffset  = Vector(0, 0, 40)
local wallRunAng    = 28
local traceDist     = 30
local wallJumpSide  = 150
local wallJumpVert  = 300
local boneAngCache  = {}
local jumpVelCache  = {}

local wallRunSounds = {
    "player/footsteps/wood1.wav",
    "player/footsteps/wood2.wav",
    "player/footsteps/wood3.wav",
    "player/footsteps/wood4.wav",
    "player/footsteps/tile1.wav",
    "player/footsteps/tile2.wav",
    "player/footsteps/tile3.wav",
    "player/footsteps/tile4.wav",
}

local wallRunAnims = {
    revolver = ACT_HL2MP_RUN_REVOLVER,
    pistol   = ACT_HL2MP_RUN_PISTOL,
    shotgun  = ACT_HL2MP_RUN_SHOTGUN,
    smg      = ACT_HL2MP_RUN_SMG1,
    ar2      = ACT_HL2MP_RUN_AR2,
    physgun  = ACT_HL2MP_RUN_PHYSGUN,
    grenade  = ACT_HL2MP_RUN_GRENADE,
    rpg      = ACT_HL2MP_RUN_RPG,
    crossbow = ACT_HL2MP_RUN_CROSSBOW,
    melee    = ACT_HL2MP_RUN_MELEE,
    melee2   = ACT_HL2MP_RUN_MELEE2,
    slam     = ACT_HL2MP_RUN_SLAM,
    fist     = ACT_HL2MP_RUN_FIST,
    normal   = ACT_HL2MP_RUN,
    camera   = ACT_HL2MP_RUN_CAMERA,
    duel     = ACT_HL2MP_RUN_DUEL,
    passive  = ACT_HL2MP_RUN_PASSIVE,
    magic    = ACT_HL2MP_RUN_DUEL,
    knife    = ACT_HL2MP_RUN_KNIFE,
}

local plyMeta = FindMetaTable("Player")
local getRunSpeed = plyMeta.GetRunSpeed
local inVehicle = plyMeta.InVehicle

local entMeta = FindMetaTable("Entity")
local getNW2Bool = entMeta.GetNW2Bool
local setNW2Bool = entMeta.SetNW2Bool
local getVelocity = entMeta.GetVelocity
local setVelocity = entMeta.SetVelocity
local getMoveType = entMeta.GetMoveType
local onGround = entMeta.OnGround
local getTable = entMeta.GetTable

local function sideTrace(ply, origin, ang, plyVel, inverted)
    origin = origin + originOffset

    local plyTbl    = getTable(ply)
    local plyTrace  = plyTbl.WallPogo
    plyTrace.start  = origin
    plyTrace.filter = ply
    plyTrace.endpos = origin + ang:Right() * (inverted and -traceDist or traceDist)

    local traceResult = util.TraceLine(plyTrace)

    if traceResult.HitWorld then
        local wallRunVel = plyVel:GetNormalized() * 10 * wallRunSpeedMult

        plyTbl.WallPogoLastHitNorm = traceResult.HitNormal

        setVelocity(ply, wallRunVel)
        setNW2Bool(ply, "WallPogo_IsWallRunning", true)
        setNW2Bool(ply, "WallPogo_IsInverted", inverted)

        if SERVER then
            local curTime = CurTime()
            local lastStep = plyTbl.WallPogoLastStep or 0

            if lastStep <= curTime and IsFirstTimePredicted() then
                ply:EmitSound(wallRunSounds[math.random(1, 8)], 100, 100)
                plyTbl.WallPogoLastStep = curTime + 0.2
            end
        end

        return true
    else
        return false
    end
end

hook.Add("SetupMove", "WallPogo_PreMove", function(ply, mv)
    if not wallPogoEnabled then return end
    local moveType = getMoveType(ply)
    local plyVel = getVelocity(ply)

    if moveType == MOVETYPE_NOCLIP or moveType == MOVETYPE_LADDER or onGround(ply) or plyVel:Length() < getRunSpeed(ply) * 0.9 or inVehicle(ply) then
        setNW2Bool(ply, "WallPogo_IsWallRunning", false)
        ply.WallPogoJumpSide = nil

        return
    end

    ply.WallPogo = ply.WallPogo or {}

    -- Try tracing to the right side first
    local origin = mv:GetOrigin()
    local plyAng = mv:GetAngles()
    local traceResult = sideTrace(ply, origin, plyAng, plyVel, false)

    -- Right side failed, let's try the left side
    if not traceResult then
        traceResult = sideTrace(ply, origin, plyAng, plyVel, true)
    end

    -- Both sides failed, let's make sure that the player is reset
    if not traceResult then
        setNW2Bool(ply, "WallPogo_IsWallRunning", false)
    end
end)

hook.Add("KeyPress", "WallPogo_WallJump", function(ply, key)
    if key ~= IN_JUMP then return end
    if not IsFirstTimePredicted() then return end
    if not getNW2Bool(ply, "WallPogo_IsWallRunning", false) then return end

    -- Make sure that the player can only jump once without jumping to a different wall first
    local plyTbl     = getTable(ply)
    local isInverted = getNW2Bool(ply, "WallPogo_IsInverted", false)
    local jumpSide   = plyTbl.WallPogoLastHitNorm
    if plyTbl.WallPogoJumpSide == jumpSide then return end

    local plyVel     = getVelocity(ply)
    local plyNorm    = plyVel:GetNormalized()
    local jumpVel    = ply:GetRight() * ply:WorldToLocal(plyVel + ply:GetPos()).y
    local velOffset  = jumpVelCache[ply] or Vector(0, 0, wallJumpVert)

    -- TODO: Try to improve this process for non-cardinal direction facing walls?
    if math.abs(plyNorm.x) < math.abs(plyNorm.y) then
        local jumpMult  = plyNorm.y > 0 and -1 or 1
        velOffset.x = jumpMult * (isInverted and -wallJumpSide or wallJumpSide) * wallJumpSideMult
        velOffset.y = 0
    else
        local jumpMult  = plyNorm.x > 0 and 1 or -1
        velOffset.y = jumpMult * (isInverted and -wallJumpSide or wallJumpSide) * wallJumpSideMult
        velOffset.x = 0
    end

    velOffset.z = wallJumpVert * wallJumpVertMult

    setVelocity(ply, jumpVel + velOffset)
    setNW2Bool(ply, "WallPogo_IsWallRunning", false)

    if SERVER then
        ply:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav", 100, 100, 0.25)
    end

    plyTbl.WallPogoJumpSide = jumpSide
    jumpVelCache[ply] = velOffset
end)

hook.Add("CalcMainActivity", "WallPogo_WallRunAnims", function(ply)
    -- TODO: Add Enhanced Camera/Gmod Legs support?
    local isWallRunning = getNW2Bool(ply, "WallPogo_IsWallRunning", false)
    local plyAnimAng = boneAngCache[ply] or Angle(0, 0, 0)

    -- Only update the player's angle when necessary
    if plyAnimAng.y ~= 0 or isWallRunning then
        local angDirection = getNW2Bool(ply, "WallPogo_IsInverted", false) and wallRunAng or -wallRunAng
        plyAnimAng.y = Lerp(FrameTime() * (isWallRunning and 4 or 5), plyAnimAng.y, isWallRunning and angDirection or 0)
        ply:ManipulateBoneAngles(ply:LookupBone("ValveBiped.Bip01_Pelvis") or 0, plyAnimAng, false)
        boneAngCache[ply] = plyAnimAng
    end

    if not isWallRunning then return end

    local curWep = ply:GetActiveWeapon()
    local newAct = wallRunAnims[curWep:GetHoldType()] or ACT_HL2MP_RUN

    return newAct, -1
end)