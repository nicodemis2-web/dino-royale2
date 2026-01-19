--[[
    Signal - Custom event system
    Similar to Roblox's BindableEvent but more flexible
]]

local Signal = {}
Signal.__index = Signal

-- Connection class
local Connection = {}
Connection.__index = Connection

function Connection.new(signal, callback)
    local self = setmetatable({}, Connection)
    self._signal = signal
    self._callback = callback
    self._connected = true
    return self
end

function Connection:Disconnect()
    if not self._connected then return end
    self._connected = false

    local signal = self._signal
    local index = table.find(signal._connections, self)
    if index then
        table.remove(signal._connections, index)
    end
end

-- Signal class
function Signal.new()
    local self = setmetatable({}, Signal)
    self._connections = {}
    self._waiting = {}
    return self
end

-- Connect a callback to the signal
function Signal:Connect(callback)
    local connection = Connection.new(self, callback)
    table.insert(self._connections, connection)
    return connection
end

-- Connect once (auto-disconnect after first fire)
function Signal:Once(callback)
    local connection
    connection = self:Connect(function(...)
        connection:Disconnect()
        callback(...)
    end)
    return connection
end

-- Fire the signal with arguments
function Signal:Fire(...)
    -- Wake up any waiting threads
    for _, thread in ipairs(self._waiting) do
        task.spawn(thread, ...)
    end
    self._waiting = {}

    -- Call all connected callbacks
    for _, connection in ipairs(self._connections) do
        if connection._connected then
            task.spawn(connection._callback, ...)
        end
    end
end

-- Wait for the signal to fire
function Signal:Wait()
    local thread = coroutine.running()
    table.insert(self._waiting, thread)
    return coroutine.yield()
end

-- Disconnect all connections
function Signal:DisconnectAll()
    for _, connection in ipairs(self._connections) do
        connection._connected = false
    end
    self._connections = {}
    self._waiting = {}
end

-- Destroy the signal
function Signal:Destroy()
    self:DisconnectAll()
    setmetatable(self, nil)
end

return Signal
