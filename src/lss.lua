local socket = require("socket")
local ssl = require("ssl")
local url    = require("socket.url")
local ltn12  = require("ltn12")

ltn12.BLOCKSIZE = 4096

local lss = {}
lss.__index = lss

local status_code = {
	[200] = "OK",
	[301] = "Moved Permanently",
	[404] = "Page not found",
	[500] = "Internal server error",
}

local function table_search(list, data)
	for i, d in ipairs(list) do
		if d == data then print("achou", i) return i end
	end
end

local function table_removedata(list, data)
	local pos = table_search(list, data)
	if pos then
        print("aquiiiii")
		table.remove(list, pos)
	end
end

function lss.new(options)
    local self = setmetatable({}, lss)
    if type(options) == "string" then options = {debug = true, host = options} end
    options = options or {}
    self._options = options
    self._debug = self._options.debug
    self._server = assert(socket.tcp())
    self._host = self._options.host or "0.0.0.0"
    if self._options.ssl then
        print("@@@@@")
        if not self._options.port then self._port = 8443 end
        local ok, ssl = pcall(require, "ssl")
        if ok then
             print("@@@@@2")
            local params = self._options.ssl
            params.mode = "server"
            params.protocol = params.protocol or "any"
            if self._debug then
                params.verify = params.verify or "none"
                params.options = params.options or "all"
            end
            local _ssl, err = ssl.newcontext(params)
            if _ssl then
                 print("@@@@@23")
                self._ssl = _ssl
                self:log("[INFO] OpneSSL enabled")
            else
                self:log("[WARN] OpenSSL loading error: %s", err)
            end
        else
            self:log("[WARN] OpenSSL loading error: %s", ssl)
        end
    else
        if not self._options.port then self._port = 8080 end
        self:log("[INFO] SSL disabled")
    end
    local res, err = self._server:bind(self._host, self._port)
    if not res then
        return nil, string.format("Unable to create webserver: %s", err)
    end
    self._server:settimeout(self._options.timeout or 300)
    assert(self._server:listen(socket._SETSIZE))
    self:log("Max connections count: %s", socket._SETSIZE)
    self:log("Server running on %s:%s", self._server:getsockname())
    self._recvt, self._sendt = {}, {}
    self._threads = {}
    self._matches = {}
    self._last_thread = 0
    self._assets = false
    return self
end

function lss:assets(path)
    self._assets = string.gsub(path, "^/", "")
end

function lss:match(...)
    local name, path, action = ...
    if select("#", ...) ~= 3 then
        action = path
        path = name
    end
    if path == true then path = "/" end
    if name == true then name = "/" end
    if type(path) ~= "string" then
        return nil, "invalid path"
    end
    if not string.match(path, "^/") then path = string.format("/%s", path) end
    path = string.gsub(path, "%W", "%%%1")
    path = string.gsub(path, "%%%*$", "(.*)")
    path = string.format("^()%s$", path)
    if not self._matches[path] then
        self._matches[#self._matches + 1] = path
    end
    self._matches[path] = {action = action, name = name}
end

function lss:log(data, ...)
    if self._debug ~= true then return end
    if type(data) == "table" then
        io.stdout:write(string.format("(lss) %s:\n", os.date("!%Y-%m-%d %H:%M:%S GMT"), data))
        for key, value in pairs(data) do io.stdout:write(string.format("   %s = %s\n", key, value)) end
    else
        io.stdout:write(string.format("(lss) %s: %s\n", os.date("!%Y-%m-%d %H:%M:%S GMT"), select("#", ...) > 0 and string.format(data, ...) or data))
    end
     io.stdout:flush()
end

local conn = {}
conn.__index = conn

function conn.new(parent, client, thread)
    local self = setmetatable({}, conn)
    self.parent = parent
    self.client = client
    self.thread = thread
    self.receiving = true
    self.sending = false
    self.datagramsize = socket._DATAGRAMSIZE
    return self
end

function conn:closecon()
    if self.closed then return end
	self:sendbody()
	self.client:close()
	self.closed = true
    print("close")
end

function conn:sendbody()
    local response = self.response
	if self.body_sended or not response then return end

	local body, client = response.body, self.client
	if #body > 0 then
		local bodytext = table.concat(body)
		response.headers["Content-Length"] = #bodytext
		self:sendheaders()
		client:send(bodytext)
	else
		self:sendheaders()
	end

	self.body_sended = true
end

function conn:setreceiving(state)
    print("setreceiving",state)
	if self.receiving == state then return end
	if self.receiving then
		table_removedata(self.parent._recvt, self.client)
	else
        print("inseriu _recvt")
		table.insert(self.parent._recvt, self.client)
	end
	self.receiving = state or false
end

function conn:setsending(state)
    print("setsending",state)
	if self.sending == state then return end
	if self.sending then
		table_removedata(self.parent._sendt, self.client)
	else
        print("inseriu sendt")
		table.insert(self.parent._sendt, self.client)
	end
	self.sending = state or false
end

function conn:error(code, text)
    local response = self.response
	if response then
		local msg = status_code[code]
		response.code = code
		response.msg = msg
		if text then
			text = text:gsub("\n", "<br>")
		end
		table.insert(response.body,
			string.format("<!DOCTYPE html><html lang='en'><body><h1>%s</h1><br><p>%s</p></body></html>", msg, text or ""))
	end
end

local startline_fmt = "HTTP/1.1 %d %s\n"
local function resp_startline(code, mess)
	return startline_fmt:format(code, mess)
end

local header_fmt = "%s: %s"
local function concat_headers(headers)
	local out = {}
	for i, k in pairs(headers) do
		local header = (header_fmt):format(i, k)
		table.insert(out, header)
	end
	return table.concat(out, "\n")
end

local args_fmt = "([^&=?]+)=([^&=?]+)"
local function parsequery(query)
	local args = {}
	for key, value in string.gmatch(query, args_fmt) do
		args[key] = url.unescape(value)
	end
	return args
end

local start_line_fmt = "(%w+)%s+(%g+)%s+(%w+)/([%d%.]+)"
local function parse_start_line(start_line)
	local request = {startline = start_line}
	request.method, request.rawurl, request.protoname, request.protover = start_line:match(start_line_fmt)
	return request
end

local header_match = "(%g+): ([%g ]+)"
local function read_request(data)
    local client = data.client
	repeat
        print("repeat",client:getstats() )
        if client:getstats() == 0 then coroutine.yield() end
		local start_line, err = client:receive("*l")
        print("repeat_after",start_line, err)

		if start_line then
			local request = parse_start_line(start_line)
			local raw_headers = {}
			request.headers = {}

			local reading = true
			while reading do
                if client:getstats() == 0 then coroutine.yield() end
				local header_line = client:receive("*l")
				reading = (header_line ~= "" and header_line ~= nil)
				if reading then
					table.insert(raw_headers, header_line)
					local key, value = string.match(header_line, header_match)
					if key then
						request.headers[key:lower()] = value
					end
				end
			end
			request.header = table.concat(raw_headers, "\n")
			request.url = url.parse(request.rawurl, {})
			return request
		elseif err == "timeout" then
			coroutine.yield()
		elseif err == "closed" then
			data.parent:log("Client closed")
			return
		else
			data.parent:log("[ERROR] Client error: %s", err)
			return
		end
	until start_line
end

function conn:sendstartline()
	if self.startline_sended then return end
	self.client:send(resp_startline(self.response.code, self.response.msg))
	self.startline_sended = true
end

function conn:sendheaders()
	local response = self.response
	if self.header_sended == true then return end
	local out = concat_headers(response.headers) .. "\n\n"
	self:sendstartline()
	self.client:send(out)
	self.header_sended = true
end

local function thread_func(data)
    local client = data.client
	if data.parent._ssl then
		repeat
			local ok, err = client:dohandshake()
			if not ok and err == "wantread" then
				data:setreceiving(true)
				data:setsending(false)
				coroutine.yield()
			elseif not ok and err == "wantwrite" then
				data:setreceiving(false)
				data:setsending(true)
				coroutine.yield()
			elseif not ok then
				data.parent:log("[ERROR] Handshake: %s", err)
				return
			end
		until ok
	end
	print("%%%%%%%%%%%%%%%%%%%%%%%")
	repeat
		data:setreceiving(true)
		data:setsending(false)
        print("%%%%%%%%%%%%%%%%%%%%%%%1")
		local request = read_request(data)
		print("%%%%%%%%%%%%%%%%%%%%%%%2")
		if request then
            data:setreceiving(false)
            data:setsending(true)
            print("****************************")
			if data.parent._ssl then request.headers.connection = nil end
			local response = {
				headers = {
					["Content-Type"] = "text/html; charset=utf-8",
					["Date"] = os.date("!%c GMT"),
				},
				body = {},
				code = 200,
				msg = "OK",
			}

			if request.headers.connection == "keep-alive" then
				client:setoption("keepalive", true)
			else
				response.headers.Connection = "close"
			end

			data.request = request
			data.response = response
  print("****************************2")
            local found = false
            for index = 1, #data.parent._matches do
                local path = data.parent._matches[index]
                local match = data.parent._matches[path]
                local action, name = match.action, match.name
                local matched, splat = string.match(request.url.path, path)
        print("****************************3",request.rawurl, path,matched, splat)
                if splat then request.url.splat = splat end
                if matched and type(action) == "string" and data.parent._assets then
                    found = true
                    coroutine.yield()
                    local filepath = request.url.path
                    filepath = string.format("./%s%s", data.parent._assets, filepath)
                    if splat then filepath = string.format("%s%s", filepath, splat) end
                    local file = io.open(string.gsub(filepath, "%.%.", ""), "rb")
                    if file then
                        local data_length = file:seek("end"); file:seek("set")
                        response.headers["Content-Length"] = tostring(data_length)
                        data:sendheaders()
                        for line in file:lines(data.datagramsize) do
                            client:send(line)
                            coroutine.yield()
                        end
                        file:close()
                    else
                        data.parent:log("[ERROR] File not found: %s", filepath)
                        data:error(404, string.format("File not found: %s", filepath))
                    end
                elseif matched and type(action) == "function" then
                    
                    print("checgou aqui &&&&&&&&&&&&&&")
                    found = true
                    coroutine.yield()
                     print("voltou")
                    local ok, err = pcall(action, data)
                    if not ok then
                        data.parent:log("[ERROR] Action %q error: %s", name, err)
                        if data.parent._debug then
                            data:error(500, string.format("Action %q error: %s", name, err))
                        else
                            data:error(500, string.format("Action %q error", name))
                        end
                    end
                end
            end
             print("**************************4")
            if not found then
                found = true
                coroutine.yield()
                data.parent:log("[ERROR] Not found: %s", request.url.path)
                data:error(404, string.format("Not found: %s", request.url.path))
            end
            print("**************************5")
            data:sendbody()
            data:closecon()
			if request.headers.connection ~= "keep-alive" then
				return
			end
		else
            print("return")
			return
		end
        print("######")
	until not request and data.closed
end

local function process_client(self, client)
    print("process_client")
    self._server:settimeout(0)
	local thread = coroutine.create(thread_func)
	local data = conn.new(self, client, thread)
	self._threads[client] = data
	table.insert(self._recvt, client)
	coroutine.resume(thread, data)
    print("voltou aqui")
    
end

local function process_subpool(self, subpool, pool)
    print("process_subpool")
    for _, client in ipairs(subpool) do
		local data = self._threads[client]
		if data then
			local cr = data.thread
			local ok, err = coroutine.resume(cr)
            if ok and coroutine.status(cr) == "dead" then
                data:closecon()
                table_removedata(pool, client)
                self._threads[client] = nil
            elseif not ok then
                self:log("[ERROR] %s in %s", err, self._last_thread)
				data:error(500, err)
                data:closecon()
                table_removedata(pool, client)
                self._threads[client] = nil
            end
		end
	end
end

function lss:update()
    local client, err = self._server:accept()
    if client then
        print("clientaq",tostring(client))
		client:settimeout(0)
		if self._ssl then
			local ssl_client, err = ssl.wrap(client, self._ssl)
			if ssl_client then
				process_client(self, ssl_client)
			else
				ssl_client:close()
				self:log("[ERROR] Wrap:", err)
			end
		else
			process_client(self, client)
		end
	elseif err == "timeout" then
       
		if #self._recvt > 0 or #self._sendt > 0 then
            --print("clientaq2")
			local readyread, readysend, err = socket.select(self._recvt, self._sendt, 0.001)
           -- print(err)
			if err ~= "timeout" then
				process_subpool(self, readyread, self._recvt)
				process_subpool(self, readysend, self._sendt)
			end
		end
	else
		self:log("Error while getting the connection: %s", err)
	end
end

function lss:start()
    self._start = true
   -- print("aqui")
    while self._start do 
        self:update()
    end
end

function lss:stop()
    self._start = false
end

local l = lss.new({
    debug = false,
    ssl = {

     --  mode = "server",
     --  protocol = "any",
       key = "example.com+5-key.pem",
       certificate = "example.com+5.pem",
      --cafile = "rootCA.pem",
  --    verify = "none",--"{"peer", "fail_if_no_peer_cert"},
      -- options = "all"--{"all", "no_sslv2", "no_sslv3"}
     -- verify = "none",
 -- options = "all",
 -- ciphers = "ALL:!ADH:@STRENGTH",

        
        }
})

l:match(true, function(p) 
        
print("okkkk")
        p:send("tes")
        
end)

l:start()