local unpack = table.unpack or unpack

local function request(self)
    --self.url == function == self.url(data)

end

local function list(...)
    return {["#"] = select("#", ...), ...}
end

local function unlist(list)
    return unpack(list, 1, list["#"])
end

local function id(instance)
    instance._ids = instance._ids + 1
    return instance._ids
end

local function compose_clone(self, compose)

end

local function compose_parse(self, compose, ...)

end

local function compose_thread(self, thread, ...)

end

local function compose_session(self, session, ...)

end

local function object_create(self, source, object, ...)

end

local function object_resume(self, source, object, ...)

end

local function receive(self, update, ...)
    --check chat source
    --check if is action/payment
    --check if is command
    --run/resume by name
    --check any event
    --run /start
end

local luagram = {}
luagram.__index = luagram

function luagram.new(options)
    assert(type(options) == "string" or type(options) == "table", "bad argument #1 (string or table expected)")

    local self = setmetatable({}, luagram)
    self._ids = 0
    self._objects = {}
    self._events = {}
    self._locales = {}
    return self
end

function luagram:btn(label, action, ...)
    assert(type(label) == "string", "bad argument #1 (string expected)")
    assert(type(action) == "function", "bad argument #2 (function expected)")

    return {
        type = "btn",
        id = id(self),
        label = label,
        action = action,
        args = list(...)
    })
end

function luagram:pay(...)
    local label, success, checkout, shipping = ...

    if type(label) == "function" then
        success, checkout, shipping = label, success, checkout

        assert(type(success) == "function", "bad argument #1 (string or function expected)")
        assert(type(checkout) == "function", "bad argument #2 (function expected)")

        if select("#", ...) > 2 then
            assert(type(shipping) == "function", "bad argument #3 (function expected)")
        end

        return {
            type = "pay",
            id = id(self),
            label = false,
            success = success,
            checkout = checkout,
            shipping = shipping,
        }
    else
        assert(type(label) == "string", "bad argument #1 (string or function expected)")
        assert(type(success) == "function", "bad argument #2 (function expected)")
        assert(type(checkout) == "function", "bad argument #3 (function expected)")

        if select("#", ...) > 3 then
            assert(type(shipping) == "function", "bad argument #4 (function expected)")
        end

        return {
            type = "pay",
            id = id(self),
            label = label,
            success = success,
            checkout = checkout,
            shipping = shipping,
        }
    end
end

function luagram:url(label, url)
    assert(type(label) == "string", "bad argument #1 (string expected)")
    assert(type(url) == "string", "bad argument #2 (string expected)")

    return {
        type = "url",
        id = id(self),
        label = label,
        url = url
    }
end

function luagram:compose(name, compose, ...)
    assert(type(name) == "string", "bad argument #1 (string expected)")
    assert(type(compose) == "table", "bad argument #2 (table expected)")

    local data = {
        type = "compose",
        id = id(self),
        name = name,
        compose = compose,
        args = list(...)
    }
    self._objects[name] = data
    return data
end

function luagram:session(name, session, ...)
    assert(type(name) == "string", "bad argument #1 (string expected)")
    assert(type(session) == "table", "bad argument #2 (table expected)")
    
    local data = {
        type = "session",
        id = id(self),
        name = name,
        session = session,
        args = list(...)
    }
    self._objects[name] = data
    return data
end

function luagram:thread(name, thread, ...)
    assert(type(name) == "string", "bad argument #1 (string expected)")
    assert(type(thread) == "function", "bad argument #2 (function expected)")

    local data = {
        type = "thread",
        id = id(self),
        name = name,
        thread = thread,
        args = list(...)
    }
    self._objects[name] = data
    return data
end

function luagram:locales(locales)
    assert(type(locales) == "table", "bad argument #1 (table expected)")
    self._locales = locales
end

function luagram:locale(text, ...)
    assert(type(text) == "string", "bad argument #1 (string expected)")

    return {
        type = "locale",
        text = text,
        args = list(...)
    }
end

function luagram:on(...)
    local event, action = ...
    if type(event) == "function" then
        self:_events[true] = event
        return event
    elseif type(event) == "string" then
        if type(action) == "function" then
            self:_events[event] = action
        elseif select("#", ...) > 1 then
            error("bad argument #2 (function expected)")
        end
        return self:_events[event]
    elseif select("#", ...) == 0 then
        return self:_events[true]
    end
    error("bad argument #1 (string or function expected)")
end

function luagram:updates(callback, ...)
    assert(type(callback) == "function", "bad argument #1 (function expected)")

    -- while true do end request get_updates
    --select(2, ...) = extra args

    
    local args = list(select(2, ...))
    self._updates = true
    while self._updates do
        xpcall(function()
            -- get updates
            if callback(true, receive()) == false then
                self._updates = false
            end
        end, function(...)
            if callback(false, ...) == false then
                self._updates = false
            end
        end)
    end
end

function luagram:receive(...)
    --extra args
    --return nil, error
end

return luagram