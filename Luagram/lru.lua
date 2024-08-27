local lru = {}
lru.__index = lru

function lru.new(size)
    local self = setmetatable({}, lru)
    self._size = size
    self._length = 0
    self._items = {}
    return self
end

function lru:set(key, value)
    local current = self._items[key]
    if current then
        if not current.up then
            self._top = current.down
        end
        if not current.down then
            self._bottom = current.up
        end
        self._items[key] = nil
        self._length = self._length - 1
    end
    if value == nil then
        return self
    end
    local item = {value = value, key = key}
    if self._top then
        self._top.up = item
        item.down = self._top
    end
    self._top = item
    if not self._bottom then
        self._bottom = item
    end
    self._items[key] = item
    self._length = self._length + 1
    if self._size and self._length > self._size then
        self._items[self._bottom.key] = nil
        self._length = self._length - 1
        if self._bottom.up then
            self._bottom.up.down = nil
            self._bottom = self._bottom.up
        else
            self._bottom = nil
            self._top = nil
        end
    end
    return self
end

function lru:get(key)
    local current = self._items[key]
    if not current then
        return nil
    end
    local value = current.value
    self:set(key, value)
    return value
end

return lru