local lte = {}
lte.__index = lte

function lte.new(template, _assert)
    local self = setmetatable({}, lte)
    if io.type(template) == "file" then
        local file, err = io.open(template, "r")
        if not file then
            return nil, err
        end
        template = file:read("*a")
        file:close()
    else
        template = tostring(template)
    end
    self._template = template
    self._vars = {}
    self._assert = _assert or function(name, value)
      if type(value) == "nil" then error(string.format("value for %q not found", name), 2) end
      return tostring(value)
    end
    return self
end

function lte:var(_var, ...)
    local current = self._vars[_var]
    if select("#", ...) > 0 then
      self._vars[_var] = ...
    end
    return current
end

function lte:parse(env, ...)
    env = env or {}
    for key, value in pairs(self._vars) do env[key] = value end
    env.__ESC = function(value) return string.gsub(tostring(value), '[&"<>]',
        { ["&"] = "&amp;", ['"'] = "&quot;", ["<"] = "&lt;", [">"] = "&gt;"})
    end
    env.__FMT = string.format
    env.__CHK = self._assert
    env.arg = env.arg or {...}
    local buffer = {"local __BUF={};"}
    for html, prefix, value in string.gmatch(string.format("%s<%%\0%%>", self._template), "(.-)<%%%s*([=&%-]*)%s*(.-)%s*%%>") do
        buffer[#buffer + 1] = string.format("__BUF[#__BUF+1]=%q;", html)
        if value == "\0" then break end
        local format
        if prefix == "=" or prefix == "&" then
            value = string.match(string.gsub(value, "^(.*)(%%[%-%+#%.%d]*[cdiouxXeEfgGqsaAp])$", function(_value, _format) format = _format return _value end), "^(.-)%s*$")
        end
        if prefix == "=" then
            if format then
                buffer[#buffer + 1] = string.format("__BUF[#__BUF+1]=__FMT(%q,__CHK(%q,%s));", format, value, value)
            else
                buffer[#buffer + 1] = string.format("__BUF[#__BUF+1]=__CHK(%q,%s);", value, value)
            end
        elseif prefix == "&" then
            if format then
                buffer[#buffer + 1] = string.format("__BUF[#__BUF+1]=__FMT((%q,__ESC(__CHK(%q,%s)));", format, value, value)
            else
                buffer[#buffer + 1] = string.format("__BUF[#__BUF+1]=__ESC(__CHK(%q,%s));", value, value)
            end
        elseif not string.match(prefix, "^%-%-") then
            buffer[#buffer + 1] = string.format("%s ", value)
        end
    end
    buffer[#buffer + 1] = "return __BUF"
    buffer = table.concat(buffer)
    local code, err = load(buffer, buffer, "t", env or {})
    if not code then
      return nil, string.format("Lua syntax error on template line %s: %s", string.match(err, ":(%d+):%s(.*)"))
    end
    if setfenv then setfenv(code, env or {}) end
    local ok, html = pcall(code, ...)
    if not ok then
      if string.match(html, "__FMT") then
        return nil, string.format("Lua error on template line %s: %s", string.match(html, ":(%d+):%s.-%((.-)%)"))
      else
        return nil, string.format("Lua error on template line %s: %s", string.match(html, ":(%d+):%s(.*)"))
      end
    end
    return table.concat(html)
end

return lte