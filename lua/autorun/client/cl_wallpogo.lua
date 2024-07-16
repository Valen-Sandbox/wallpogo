local angTarget  = Angle(0, 0, 0)
local wallRunAng = 7

local getNW2Bool = FindMetaTable("Entity").GetNW2Bool

hook.Add("CalcView", "WallPogo_WallrunViewAngles", function(ply, _, ang)
    local isWallRunning = getNW2Bool(ply, "WallPogo_IsWallRunning", false)

    if not isWallRunning and angTarget.z == 0 then return end

    local isInverted = getNW2Bool(ply, "WallPogo_IsInverted", false)
    local angDirection = isInverted and wallRunAng or -wallRunAng
    angTarget.z = Lerp(FrameTime() * (isWallRunning and 2 or 4), angTarget.z, isWallRunning and angDirection or 0)
    ang:Add(angTarget)
end)