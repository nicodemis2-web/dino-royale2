--[[
    Math Utilities
    Common mathematical functions for game calculations
]]

local Math = {}

-- Lerp between two values
function Math.lerp(a, b, t)
    return a + (b - a) * t
end

-- Clamp a value between min and max
function Math.clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

-- Round to nearest decimal place
function Math.round(value, decimals)
    decimals = decimals or 0
    local mult = 10 ^ decimals
    return math.floor(value * mult + 0.5) / mult
end

-- Map a value from one range to another
function Math.map(value, inMin, inMax, outMin, outMax)
    return outMin + (value - inMin) * (outMax - outMin) / (inMax - inMin)
end

-- Get random float between min and max
function Math.randomFloat(min, max)
    return min + math.random() * (max - min)
end

-- Get random point in circle
function Math.randomPointInCircle(radius)
    local angle = math.random() * math.pi * 2
    local r = math.sqrt(math.random()) * radius
    return Vector3.new(
        math.cos(angle) * r,
        0,
        math.sin(angle) * r
    )
end

-- Get distance between two Vector3 positions (2D, ignoring Y)
function Math.distance2D(pos1, pos2)
    return ((pos1.X - pos2.X)^2 + (pos1.Z - pos2.Z)^2)^0.5
end

-- Get distance between two Vector3 positions (3D)
function Math.distance3D(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

-- Get angle between two positions (in degrees)
function Math.angleBetween(from, to)
    local direction = to - from
    return math.deg(math.atan2(direction.Z, direction.X))
end

-- Normalize angle to 0-360
function Math.normalizeAngle(angle)
    angle = angle % 360
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

-- Smooth damp (for smooth camera, etc.)
function Math.smoothDamp(current, target, currentVelocity, smoothTime, maxSpeed, deltaTime)
    smoothTime = math.max(0.0001, smoothTime)
    local omega = 2 / smoothTime

    local x = omega * deltaTime
    local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)

    local change = current - target
    local originalTo = target

    -- Clamp maximum speed
    local maxChange = maxSpeed * smoothTime
    change = Math.clamp(change, -maxChange, maxChange)
    target = current - change

    local temp = (currentVelocity + omega * change) * deltaTime
    currentVelocity = (currentVelocity - omega * temp) * exp

    local output = target + (change + temp) * exp

    -- Prevent overshooting
    if (originalTo - current > 0) == (output > originalTo) then
        output = originalTo
        currentVelocity = (output - originalTo) / deltaTime
    end

    return output, currentVelocity
end

-- Weighted random selection from a table
function Math.weightedRandom(weights)
    local totalWeight = 0
    for _, weight in pairs(weights) do
        totalWeight = totalWeight + weight
    end

    local random = math.random() * totalWeight
    local cumulative = 0

    for key, weight in pairs(weights) do
        cumulative = cumulative + weight
        if random <= cumulative then
            return key
        end
    end

    -- Fallback (shouldn't reach here)
    for key, _ in pairs(weights) do
        return key
    end
end

return Math
