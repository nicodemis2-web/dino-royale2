--[[
    Promise - Asynchronous operation handling
    Simple Promise implementation for Roblox
]]

local Promise = {}
Promise.__index = Promise

-- Promise states
local PENDING = "Pending"
local FULFILLED = "Fulfilled"
local REJECTED = "Rejected"

function Promise.new(executor)
    local self = setmetatable({}, Promise)

    self._state = PENDING
    self._value = nil
    self._reason = nil
    self._onFulfilled = {}
    self._onRejected = {}

    local function resolve(value)
        if self._state ~= PENDING then return end

        self._state = FULFILLED
        self._value = value

        for _, callback in ipairs(self._onFulfilled) do
            task.spawn(callback, value)
        end
    end

    local function reject(reason)
        if self._state ~= PENDING then return end

        self._state = REJECTED
        self._reason = reason

        for _, callback in ipairs(self._onRejected) do
            task.spawn(callback, reason)
        end
    end

    task.spawn(function()
        local success, err = pcall(executor, resolve, reject)
        if not success then
            reject(err)
        end
    end)

    return self
end

-- Create an immediately resolved promise
function Promise.resolve(value)
    return Promise.new(function(resolve)
        resolve(value)
    end)
end

-- Create an immediately rejected promise
function Promise.reject(reason)
    return Promise.new(function(_, reject)
        reject(reason)
    end)
end

-- Then handler
function Promise:andThen(onFulfilled, onRejected)
    return Promise.new(function(resolve, reject)
        local function handleFulfilled(value)
            if type(onFulfilled) == "function" then
                local success, result = pcall(onFulfilled, value)
                if success then
                    resolve(result)
                else
                    reject(result)
                end
            else
                resolve(value)
            end
        end

        local function handleRejected(reason)
            if type(onRejected) == "function" then
                local success, result = pcall(onRejected, reason)
                if success then
                    resolve(result)
                else
                    reject(result)
                end
            else
                reject(reason)
            end
        end

        if self._state == FULFILLED then
            task.spawn(handleFulfilled, self._value)
        elseif self._state == REJECTED then
            task.spawn(handleRejected, self._reason)
        else
            table.insert(self._onFulfilled, handleFulfilled)
            table.insert(self._onRejected, handleRejected)
        end
    end)
end

-- Catch handler (shorthand for andThen with only rejection handler)
function Promise:catch(onRejected)
    return self:andThen(nil, onRejected)
end

-- Finally handler (runs regardless of outcome)
function Promise:finally(callback)
    return self:andThen(
        function(value)
            callback()
            return value
        end,
        function(reason)
            callback()
            error(reason)
        end
    )
end

-- Wait for the promise to settle (blocking)
function Promise:await()
    if self._state == FULFILLED then
        return self._value
    elseif self._state == REJECTED then
        error(self._reason)
    end

    local thread = coroutine.running()
    local resolved = false

    self:andThen(function(value)
        resolved = true
        task.spawn(thread, true, value)
    end, function(reason)
        resolved = true
        task.spawn(thread, false, reason)
    end)

    local success, result = coroutine.yield()

    if success then
        return result
    else
        error(result)
    end
end

-- Wait for all promises to resolve
function Promise.all(promises)
    return Promise.new(function(resolve, reject)
        local results = {}
        local remaining = #promises

        if remaining == 0 then
            resolve(results)
            return
        end

        for i, promise in ipairs(promises) do
            promise:andThen(function(value)
                results[i] = value
                remaining = remaining - 1
                if remaining == 0 then
                    resolve(results)
                end
            end, function(reason)
                reject(reason)
            end)
        end
    end)
end

-- Wait for first promise to settle
function Promise.race(promises)
    return Promise.new(function(resolve, reject)
        for _, promise in ipairs(promises) do
            promise:andThen(resolve, reject)
        end
    end)
end

-- Create a promise that resolves after a delay
function Promise.delay(seconds)
    return Promise.new(function(resolve)
        task.delay(seconds, function()
            resolve()
        end)
    end)
end

-- Try to execute a function, returning a promise
function Promise.try(func, ...)
    local args = {...}
    return Promise.new(function(resolve, reject)
        local success, result = pcall(func, unpack(args))
        if success then
            resolve(result)
        else
            reject(result)
        end
    end)
end

return Promise
