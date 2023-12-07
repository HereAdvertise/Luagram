--local ltn12 = require("ltn12") -- luarocks install luasocket
--local cjson = require("cjson") -- luarocks install lua-cjson

local unpack = table.unpack or unpack

local function list(...)
    return {["#"] = select("#", ...), ...}
end

local function unlist(list)
    return unpack(list, 1, list["#"])
end

local function id(self)
    self.__class._ids = self.__class._ids + 1
    return self.__class._ids
end

local http_provider, json_encoder, json_decoder

local function detect()
    if http_provider then
        return
    end
    local ok = pcall(_G.GetRedbeanVersion)
    if ok then
        http_provider = Fetch
        json_encoder = EncodeJson
        json_decoder = DecodeJson
        return
    end
    if _G.ngx then
        local http = require("lapis.nginx.http")
        http_provider = function(url, options)
            return http.simple(url, options)
        end
        local json = require("cjson")
        json_encoder = json.encode
        json_decoder = json.decode
        return
    end
    local http = require("ssl.https")
    local ltn12 = require("ltn12")
    http_provider = function(url, options)
        local out = {}
        options.source = ltn12.source.string(options.body)
        options.sink = ltn12.sink.table(out)
        options.url = url
        local _, status, headers = http.request(options)
        local response = table.concat(out)
        return response, status, headers
    end
    local json = require("cjson")
    json_encoder = json.encode
    json_decoder = json.decode
end

detect()

local function request(self, url, options)
    local http_provider = self.__class._http_provider or http_provider
    local response, response_status, headers = http_provider(url, options)
    local response_headers
    if status == 200 and type(headers) == "table" then
        response_headers = {}
        for key, value in pairs(headers) do
            response_headers[string.lower(key)] = value
        end
    end
    return response, response_status, response_headers or headers
end

local function telegram(self, method, data)
    local api = self.__class._api or "https://api.telegram.org/bot%s/%s"
    api = string.format(api, self.__class._token, method)
    local body = json_encoder(data)
    local headers = {
        ["content-type"] = "application/json",
        ["content-length"] = #body
    }
    if self.__class._headers then
        for key, value in pairs(self.__class._headers) do
            headers[string.lower(key)] = value
        end
    end
    local response, response_status, response_headers = request(self, api, {
        method = "POST",
        body = body,
        headers = headers
    })
    --check for errors
    local result = json.decoder(response)
    return result, response, response_status, response_headers
end

local function escape(text)
    return string.gsub(text, '[<>&"]', {
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ["&"] = "&amp;",
        ['"'] = "&quot;"
    })
end

local function locale(self, value, number)
    local locales = self.__class._locales
    local result = value
    if type(value) == "string" then
        if locales and self._language_code then
            local language_locales = locales[self._language_code]
            if language_locales and language_locales[value] then
                result = language_locales[value]
                if type(result) == "table" then
                    if number then
                        if type(language_locales[1]) == "function" then
                            return result[language_locales[1](number)] or value
                        else
                            return result[number] or result[#result] or value
                        end
                    else
                        return result[1] or value
                    end
                end
            end
        end
    end
    return result
end

local function format(values)
    local result = string.gsub(values[1], "(%%?)(%%[%-%+#%.%d]*[cdiouxXeEfgGqsaAp])%[(%w+)%]", function(prefix, specifier, name)
        if prefix == "%" then
            return string.format("%%%s[%s]", specifier, name)
        end
        if not values[name] then
            error("no key '" .. name .. "' for string found")
        end
        return string.format(specifier, (string.gsub(values[name], "%%", "%%%%")))
    end)
    local ok
    ok, result = pcall(string.format, result, unpack(values, 2))
    if not ok then
        error("invalid string found")
    end
    local number
    for key, value in pairs(values) do
        if key ~= 1 and tonumber(value) then
            number = tonumber(value)
            break
        end
    end
    return result, number
end

local function text(self, value)
    if type(value) == "table" then
        if type(value[1]) == "string" then
            return locale(self, format(value))
        else
            error("invalid text")
        end
    end
    return value
end

local function catch_error()
    return function(...)
        error((...), -1, select(2, ...))
    end
end

local function message_parse(self, message, ...)
    -- é muito simples parsear uma mensagem

    local users = self.__class._users

    local user = users:get(self._chat_id)

    if not user then
        message:catch("user not found")
        return
    end

    local output = {}
    local texts = {}
    local buttons = {}
    local interactions = {}
    local row = {}
    local data = {
        parse_mode = "HTML"
    }

    local media, media_type, media_extension
    local title, description, price

    local multipart = false
    local method = "message"

    local transaction = false
    local transaction_label = false
    local payload

    local open_tags = {}
    local function close_tags()
        for index = #open_tags, 1, -1  do
            texts[#texts + 1] = open_tags[index]
        end
        open_tags = {}
    end

    local index = 1
    while index <= #message do
        local item = message[index]
        if type(item) == "table" and item._type then

            -- runtime
            if item._type = "run" then
                message._index = index + 1
                local _ = (function(ok, ...)
                    if not ok then
                        message:catch(...)
                    end
                end)(pcall(item.value, self, unlist(message.args))) --xpcall?
                message._index = nil

            -- texts
            elseif item._type = "text" then
                texts[#texts + 1] = escape(text(self, item.valu))
                close_tags()
            elseif item._type = "bold" then
                open_tags[#open_tags + 1] = "</b>"
                texts[#texts + 1] = "<b>"
                if item.value then
                    texts[#texts + 1] = escape(text(self, item.value))
                    close_tags()
                end
            elseif item._type = "italic" then
                open_tags[#open_tags + 1] = "</i>"
                texts[#texts + 1] = "<i>"
                if item.value then
                    texts[#texts + 1] = escape(text(self, item.value))
                    close_tags()
                end
            elseif item._type = "underline" then
                open_tags[#open_tags + 1] = "</u>"
                texts[#texts + 1] = "<u>"
                if item.value then
                    texts[#texts + 1] = escape(text(self, item.value))
                    close_tags()
                end
            elseif item._type = "spoiler" then
                open_tags[#open_tags + 1] = "</tg-spoiler>"
                texts[#texts + 1] = "<tg-spoiler>"
                if item.value then
                    texts[#texts + 1] = escape(text(self, item.value))
                    close_tags()
                end
            elseif item._type = "strike" then
                open_tags[#open_tags + 1] = "</s>"
                texts[#texts + 1] = "<s>"
                if item.value then
                    texts[#texts + 1] = escape(text(self, item.value))
                    close_tags()
                end
            elseif item._type = "link" then
                close_tags()
                texts[#texts + 1] = '<a href="'
                texts[#texts + 1] = escape(item.href)
                texts[#texts + 1] = '">'
                texts[#texts + 1] = escape(text(self, item.value))
                texts[#texts + 1] = "</a>"
            elseif item._type = "mention" then
                close_tags()
                texts[#texts + 1] = '<a href="tg://user?id='
                texts[#texts + 1] = escape(item.user)
                texts[#texts + 1] = '">'
                texts[#texts + 1] = escape(text(self, item.value))
                texts[#texts + 1] = "</a>"
            elseif item._type = "emoji" then
                close_tags()
                texts[#texts + 1] = '<tg-emoji emoji-id="'
                texts[#texts + 1] = escape(item.value)
                texts[#texts + 1] = '">'
                texts[#texts + 1] = escape(text(self, item.emoji))
                texts[#texts + 1] = "</tg-emoji>"
            elseif item._type = "mono" then
                close_tags()
                texts[#texts + 1] = "<code>"
                texts[#texts + 1] = escape(text(self, item.value))
                texts[#texts + 1] = "</code>"
            elseif item._type = "pre" then
                close_tags()
                texts[#texts + 1] = "<pre>"
                texts[#texts + 1] = escape(text(self, item.value))
                texts[#texts + 1] = "</pre>"
            elseif item._type = "code" then
                close_tags()
                if item.language then
                    texts[#texts + 1] = '<pre><code class="language-'
                    texts[#texts + 1] = escape(item.language)
                    texts[#texts + 1] = '">'
                    texts[#texts + 1] = escape(text(self, item.value))
                else
                    texts[#texts + 1] = "<pre><code>"
                    texts[#texts + 1] = escape(text(self, item.value))
                end
                texts[#texts + 1] = "</code></pre>"
            elseif item._type = "line" then
                if item.value then
                    texts[#texts + 1] = escape(text(self, item.value))
                end
                close_tags()
                texts[#texts + 1] = "\n"
            elseif item._type = "html" then
                close_tags()
                texts[#texts + 1] = text(self, item.value)

            -- others
            elseif item._type = "media" then
                media = item._media
            elseif item._type = "title" then
                title = item._title
            elseif item._type = "description" then
                description = item._description
            elseif item._type = "price" then
                price = item._price
            elseif item._type = "data" then
                data[item._key] = data[item._value]

            -- buttons
            elseif item._type = "action" then
                -- criar um action aqui
                --gerar uuid
                --adicionar À sessão
                local uuid
                local label = text(self, item.label)
                if type(item.action) == "string" then
                    uuid = string.format("luagram_event_%s", item.action)
                else
                    uuid = string.format("luagram_action_%s_%s_%s", self._chat_id, id(self), os.time())
                    interactions[#interactions + 1] = uuid
                    local interaction = {
                        message = message,
                        label = label,
                        value = item.action,
                        interactions = interactions,
                        args = 1 --> qual args?
                    }
                    user.interactions[uuid] = interaction
                end
                row[#row + 1] = {
                    text = label,
                    callback_data = uuid
                }
            elseif item._type = "location" then
                row[#row + 1] = {
                    text = text(self, item.label),
                    url = item.location
                }
            elseif item._type = "transaction" then
                if transaction then
                    error("transaction previously defined for this message")
                end

                transaction = true

                local label = text(self, item.label)

                if item.label ~= false then
                    table.insert(buttons, 1, {
                        text = label,
                        pay = true
                    })
                else
                    --não pode haver mais nenhum botão nesse caso
                    transaction_label = true
                end

                local uuid = string.format("luagram_transaction_%s_%s_%s", self._chat_id, id(self), os.time())

                local interaction = {
                    message = message,
                    label = label,
                    value = item.transaction,
                    interactions = interactions,
                    args = 1 --> qual args?
                }

                payload = uuid

                user.interactions[uuid] = interaction
                --se label for igual a false:
                --colocar esse botão no primeiro item da lista

            elseif item._type = "row" then
                buttons[#buttons + 1] = row
                row = {}
            end
        end
        index = index + 1
    end
    close_tags()
    if #row > 0 then
        buttons[#buttons + 1] = row
    end

    if transaction and transaction_label and #buttons > 0 then
        error("add a label to transaction function to define actions in this message")
    end

    if media then
        if string.match(string.lower(media), "^https?://[^%s]+$") then
            media_type = "url"
        elseif string.match(media, "[/\\]") then
            media_type = "path"
            multipart = true
        else
            media_type = "id"
        end
    end

    if transaction and media and media_type == "url" then
        if not data.photo_url then
            data.photo_url = media
            media = nil
        end
    elseif transaction and media then
        error("you can only define an url for transaction media")
    end

    if transaction then
        --check title
        --check description
        --check price
        if not data.payload then
            data.payload = payload
        end
    end

    if media_type == "id" then
        local response, err = self.__class:api("get_file", {
            file_id = media
        })

        if not response then
            error(err)
        end

        local file_path = string.lower(assert(response.file_path, "file_path not found"))

        if file_path:match("animations") then
            method = "animation"
        elseif file_path:match("photos") then
            method = "photo"
        else
            error(string.format("unknown file type: %s", file_path))
        end

    elseif media_type == "url" then
        local response, status, headers = request(media)

        if not response then
            error(status)
        end

        if status ~= 200 then
            error(string.format("unable to fetch media (%s): %s", media, status))
        end

        local content_type

        if type(headers) == "table" and headers["content-type"] then
            content_type = string.lower(headers["content-type"])

            if content_type == "image/gif" then
                method = "animation"
            elseif content_type == "image/png" or content_type == "image/jpg" or content_type == "image/jpeg" then
                method = "photo"
            else
                error(string.format("unknown file content type (%s): %s", media, content_type))
            end
        else
            error(string.format("content type not found for media %s", media))
        end

    elseif media_type == "path" then

        local file, err = io.open(media, "rb")

        if not file then
            error(err)
        end

        file:seek("set")
        if not method and file:read(4) == "\x47\x49\x46\x38" then -- gif
            method = "animation"
        end
        file:seek("set")
        if not method and file:read(8) == "\x89\x50\x4E\x47\x0D\x0A\x1A\x0A" then -- png
            method = "photo"
        end
        file:seek("set")
        if not method and file:read(3) == "\xFF\xD8\xFF" then -- jpg, jpeg
            method = "photo"
        end
        file:close()
        if not method then
            error(string.format("unknown media signature"))
        end
    else
        error("unknown media type")
    end

    --lançar um erro aqui se for transactrion e não haver payment_successfully event
    --se for transaction colocar pra mostrar recibo e mdata
    --olhar botgram

    message._multipart = multipart
   

    --aqui deve processar de acordo com o tipo da mensagem
    --se for transaction:
    --deve checar se há os campos certos
    --se for media deve informar o field certo de acordo
    --se a media for um io.open
    --deve enviar via multipart

    for key, value in pairs(data) do
        output[key] = value
    end

    return output
end

local function send(self, chat_id, language_code, name, ...)

    local users = self.__class._users
    local catch = self.__class._catch
    local objects = self.__class._objects

    local user = users:get(chat_id)

    if not user then
        users:set(chat_id, {
            interactions = {}
        })
        user = users:get(chat_id)
    end

    local object = objects[name]

    if not object then
        catch(string.format("object not found: %s", name))
        return
    end

    local chat = self.__class:chat(chat_id, language_code)

    if object._type == "message" then

        local this = object:clone()

        this.send = function(self, ...)
            chat:send(...)
            return self
        end

        this.say = function(self, ...)
            chat:say(...)
            return self
        end

        local result = message_parse(chat, this, ...)

        --send

    elseif object._type == "session" then

        -- aqui deve-se criar uma nova sessão
        --chmar a nova sessão

        if not object._main then
            catch(string.format("undefined main session thread: %s", name))
            return
        end

        user.thread = {}

        local thread = user.thread

        chat.listen =  function(_, match)
            if type(match) == "function" then
                thread.match = match
            else
                thread.match = nil
            end
            return coroutine.yield()
        end

        thread.main = coroutine.create(object._main)
        thread.object = object
        thread.self = chat

        local ok, err = coroutine.resume(thread.main, thread.self, unlist(select("#", ...) > 0 and list(...) or object._args))

        if not ok then
            object:catch(string.format("error on execute main session thread (%s): %s", name, err))
            return
        end

        if coroutine.status(thread.main) == "dead" then
            user.thread = nil
        end

    else

        catch(string.format("undefined object type: %s", name))
        return

    end

    return true

    -- essa função é chamada para criar um novo objeto para self
    
    --?? uma coisa que devemos fazer é preporcessar o name se self._objects[name]
    --porque pode ser passado nomes traduzíveis
    --mas o problema, em que momento?
    --no momento da declação não é possivel, pois pode ser passado olocale depois
    --na prórpia função locale então??
    --fazer um loop lá e verificar se key é um text ou i18n <------
    -- também fazer um loop caso já haja locales
    --então o certo é criar uma função

    --verificar o ypo do objetoii

    --se message: parsear um novo clone da mensage
    --(criar metodo: chat, send)
    --enviar

    -- session: criar uma sessao nova

    --retirnar true caso sucesso

end

local modules = {}

modules.message = function(self)

    self:class("message", function(self, name, ...)
        if name == nil then
            name = "/start"
        end

        -- talvez usar a funaçõ text() aqui para aceitar names localizados podem ser útil
        -- {""}
        -- exceção é /start
        -- mesma coisa para a session
        -- mas para detectar o idioma (para a função text) 
        -- necessário ter o update aqui
        -- mas nesse caso não será possível salvar essa classe em __class
        --talvez seja necessário fazer self.__class._objects[name] = self na função receive mesmo

        self._type = "message"
        self._id = id(self)
        self._args = list(...)
        self._catch = catch_error
        self._name = name
        if name ~= false then
            self.__class._objects[name] = self
        end
    end)

    local message = self.message

    message.clone = function(self)
        local clone = self.__class:message(false)
        for key, value in pairs(self) do
            if key ~= "_id" and key ~= "__class" then
                if type(value) == "table" then
                    local copy = {}
                    for copy_key, copy_value in pairs(value) do
                        copy[copy_key] = copy_value
                    end
                    clone[key] = copy
                elseif type(value) ~= "function" then
                    clone[key] = value
                end
            end
        end
        if not clone._source then
            clone._source = self
        end
        return clone, self
    end

    local function insert(self, data)
        if not self._index then
            table.insert(self, data)
        else
            table.insert(self, self._index, data)
        end
    end

    local function simple(_type)
        return function(self, ...)
            local index, value = ...
            local _index = self._index
            if type(index) == "number" and select("#", ...) > 1 then
                self._index = index
            else
                value = index
            end
            insert(self, {
                _type = _type,
                value = value
            })
            self._index = _index
            return self
        end
    end

    local items = {
        "text", "bold", "italic", "underline", "spoiler", "strike", "mono", "pre", "html"
    }

    for index = 1, #items do
        local _type = items[index]
        message[_type] = simple(_type)
    end

    message.run = function(self, ...)

    end

    message.link = function(self, ...)

    end

    message.mention = function(self, ...)

    end

    message.emoji = function(self, ...)

    end

    message.code = function(self, ...)

    end

    message.line = function(self, ...)

    end

    message.media = function(self, ...)

    end

    message.title = function(self, ...)

    end

    message.description = function(self, ...)

    end

    message.price = function(self, ...)

    end

    message.data = function(self, ...)

    end

    message.action = function(self, ...)

    end

    message.location = function(self, ...)

    end

    message.transaction = function(self, ...)

    end

    message.row = function(self, ...)

    end

    return self
end

modules.session = function(self)

    self:class("session", function(self, name, ...)
        if name == nil then
            name = "/start"
        end

        self._type = "session"
        self._id = id(self)
        self._name = name
        self._args = list(...)
        self._catch = catch_error
        self.__class._objects[name] = self
    end)

    local session = self.session

    session.main = function(self, main)
        self._main = main
        return self
    end

    session.catch = function(self, catch)
        self._catch = catch
        return self
    end

    return self
end

modules.chat = function(self)

    self:class("chat", function(self, chat_id, language_code)
        self._type = "chat"
        self._chat_id = chat_id
        self._language_code = language_code
    end)

    local chat = self.chat

    chat.send = function(self, name, ...)
        send(self, self._chat_id, name, ...)
        return self
    end

    chat.say = function(self, value)
        self.__class:api("send_message", {
            chat_id = self._chat_id,
            value = text(self, value)
        })
        return self
    end

    chat.api = function(self, method, data)
        data.chat_id = self._chat_id
        return self.__class:api(method, data), self
    end

    return self
end

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

local luagram = {}
luagram.__index = luagram

function luagram.new(options)
    local self = setmetatable({}, luagram)

    if type(options) == "string" then
        options = {
            token = options
        }
    end

    assert(type(options) == "table", "invalid param: options")
    assert(type(options.token) == "string", "invalid token")

    self._ids = 0
    self._objects = {}
    self._events = {}
    self._users = lru.new(self.options.cache or 1024)
    self._actions = {}
    self._catch = catch_error

    self:module("message")
    self:module("session")
    self:module("chat")

    return self
end

function luagram:class(name, new)
    local class = {}
    class.__index = class
    self[name] = setmetatable({}, {
    __call = function(_, base, ...)
        local self = setmetatable({}, class)
        self.__name = name
        self.__class = base
        return (new and new(self, ...)) or self
    end,
    __index = function(_, key)
        return class[key]
    end,
    __newindex = function(_, key, value)
        class[key] = value
    end
    })
    return self
end

function luagram:module(name, ...)
    if modules[name] then
        return modules[name](self, ...) or self, self
    end
    local path = package.path
    package.path = "./modules/?.lua;" .. path
    local ok, module = pcall(require, name)
    package.path = path
    if not ok then
        error("module '" .. name .. "' not found")
    end
    return module(self, ...) or self, self
end

function luagram:locales(locales)

    if type(locales) == "string" then
        local path = package.path
        package.path = "./locales/?.lua;" .. path
        local ok, module = pcall(require, locales)
        package.path = path
        if not ok then
            error("module '" .. locales .. "' not found")
        end
        locales = module
    end

    self._locales = locales
    return self
end

function luagram:api(method, data)

    return self
end

function luagram:on(event, callback)
    if type(event) == "function" then
        callback = event
        event = true
    end
    self._events[event] = callback
    return self
end

local function callback_query(self, chat_id, language_code, update_data)

    local data = update_data.data

    if not data:match("^luagram_action_%d+_%d+_%d+$") then
        return false
    end

    local user = self._users:get(chat_id)

    if not user then
        return false
    end

    local action = user.interactions[data]

    if not action then
        return false
    end

    local answer = {
        cache_time = 0
    }

    if action.lock then
        answer.callback_query_id = update_data.id
        self.__class:api("answer_callback_query", answer)
        return true
    end

    action.lock = true

   

    -- necessáriorealizar uma copia da mensagem original
    -- essa mensagem é passada a função
    -- como realizar uma cópia de maneira adequada?
    -- criando  uma classe (talvez um argumento false)
    -- então copiar todos os itens do original e jogar no item novo novamente
    -- provavelmente a melhor maneira

    local this = action.message:clone()

    this._update_data = update_data
    this._update_type = "callback_query"
    this._language_code = language_code
    this._chat_id = chat_id

    local chat = self:chat(this._chat_id, this._language_code)

    this.say = function(self, ...)
        chat:say(...)
        return self
    end

    this.send = function(self, ...)
        chat:send(...)
        return self
    end

    this.this = function(self)
        for index = 1, #self do
            if type(self[index]) == "table" and self[index]._type == "action" and self[index].id == action.id then
                self[index].index = index
                return self[index], self
            end
        end
        return nil, self
    end

    this.redaction = function(self, label, action, ...)
        local this = self:this()
        label = label or this.label
        action = action or this.action
        local args = select("#", ...) > 0 and list(...) or this.args
        self:remove(this.index)
        self:action(this.index, label, action, args)
        return self
    end

    this.clear = function(self, _type)
        local buttons = {
            action = true, location = true, transaction = true, row = true
        }
        local texts ={
            text = true, bold = true, italic = true, underline = true, spoiler = true, strike = true, link = true, mention = true, mono = true, pre = true, line = true, html = true
        }
        for index = 1, #self do
            local item = self[index]
            if _type == "buttons" and type(item) == "table" then
                if item._type == buttons[_type] then
                    self[index] = true
                end
            elseif _type == "texts" and type(item) == "table" then
                if item._type == texts[_type] then
                    self[index] = true
                end
            end
        end
        return self
    end

    this.notify = function(self, value)
        if not answer.text then
            answer.text = {}
        end
        answer.text[#answer.text + 1] = text(self, value)
        return self
    end

    this.redirect = function(self, url)
        answer.url = url
        return self
    end

    this.alert = function(self)
        answer.show_alert = true
        return self
    end

    local _ = (function(ok, result, ...)

        if not ok then
            --catch: result
        end

        if result == true then
            this = message_clone._source:clone()
        elseif result == false then
            this:clear("buttons")
        elseif type(result) == "string" then
            local object = self.__class._objects[result]
            if object then
                if object._type == "message" then
                    this = object:clone()
                elseif  object._type == "session" then
                    --call session
                    --pssar os args
                    return
                else
                    -- error: invalid object
                end
            else
                --error: object not found
            end
        elseif type(result) == "table" and result._type == "session" then
            --call session
            --passar os args
            return
        elseif type(result) == "table" and result._type == "message" then
            this = result
        elseif result == nil then
            return
        else
            --catch error
        end

        --com o result, realizar a mensagem_parse aqui
        --olhar a mensagem original e a parseada
        -- havendo incompatibilidadde
        --enviar uma mensagem nova (algumas resultados devem remover o teclado da original aidna)

        -- message_parse.
        -- edit current message

        --necessário fazer um loop em action.interactions
        --cada key deve remover o action user.actions[...] = nil
        --caso a mensagem antiga precise for alterada
        --ou seja, chegue até aqui

        if action.message._transaction then
            --mensagem antiga é uma transaction
            --não pode ser alterada
            --enviar uma nova mensagem aqui

            --verificar se é possível alterar o teclado ainda
            --acredito que não
            --nesse caso se a transaction possuir teclado, o que fazer??
            --inutilizar (action.transactions???)
            return
        end

        if action.message._media and not this._media then
            this._media = action.message._media

        elseif not action.message._media and this._media then
            --remover os botões da mensagem antiga
            --enviar uma nova mensagem

            return
        end

    end)(pcall(action.action, message_clone, unlist(action.args))) -- unlist(select("#", ...) > 0 and list(...) or action.args)

    action.lock = false

    if type(answer.text) == "table" then
        answer.text = table.concat(answer.text)
    end
    answer.callback_query_id = update_data.id
    self.__class:api("answer_callback_query", answer)

    return true
end

local function shipping_query(self, chat_id, language_code, update_data)

    local payload = update_data.invoice_payload

    if not payload:match("^luagram_transaction_%d+_%d+_%d+$") then
        return false
    end

    local user = self._users:get(chat_id)

    if not user then
        return false
    end

    local transaction = user.interactions[payload]

    local catch = transaction.message.catch

    if not transaction then
        return false
    end

    local this = self:chat(this._chat_id, this._language_code)

    this.status = function(self)
        return "shipping_query", self
    end

    this.say = function(self, ...)
        this:say(...)
        return self
    end

    this.send = function(self, ...)
        this:send(...)
        return self
    end

    local _ = (function(ok, ...)

        if not ok then
            self.__class:api("answer_shipping_query", {
                shipping_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
            })
            return catch(string.format("error on proccess shipping query: %s", ...))
        end

        local result = ...

        if type(result) == "string" then
            self.__class:api("answer_shipping_query", {
                shipping_query_id = update_data.id,
                ok = false,
                error_message = result
            })
        elseif result == false then
            self.__class:api("answer_shipping_query", {
                shipping_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Sorry, delivery to your desired address is unavailable."})          
            })
        elseif select("#", ...) >  0 then
            local results = {...}
            local options = {}
            for index = 1, #results do
                local current = results[index]
                if type(current) == "table" and current.id and current.title and current.prices then
                    options[#options + 1] = {
                        id = current.id,
                        title = current.title,
                        prices = current.prices
                    }
                else
                    self.__class:api("answer_shipping_query", {
                        shipping_query_id = update_data.id,
                        ok = false,
                        error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
                    })
                    return catch(string.format("error on proccess shipping query: invalid return value"))
                end
            end 
            self.__class:api("answer_shipping_query", {
                shipping_query_id = update_data.id,
                ok = true,
                shipping_options = options
            })
            return true
        else
            self.__class:api("answer_shipping_query", {
                shipping_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
            })
            return catch(string.format("error on proccess shipping query: invalid return value"))
        end

    end)(pcall(transaction.transaction, this, unlist(action.args))) -- unlist(select("#", ...) > 0 and list(...) or action.args)

end

local function pre_checkout_query(self, chat_id, language_code, update_data)

    local payload = update_data.invoice_payload

    if not payload:match("^luagram_transaction_%d+_%d+_%d+$") then
        return false
    end

    local user = self._users:get(chat_id)

    if not user then
        return false
    end

    local transaction = user.interactions[payload]

    local catch = transaction.message.catch

    if not transaction then
        return false
    end

    local this = self:chat(this._chat_id, this._language_code)

    this.status = function(self)
        return "pre_checkout_query", self
    end

    this.say = function(self, ...)
        this:say(...)
        return self
    end

    this.send = function(self, ...)
        this:send(...)
        return self
    end

    local _ = (function(ok, ...)

        if not ok then
            self.__class:api("answer_pre_checkout_query", {
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
            })
            return catch(string.format("error on proccess pre checkout query: %s", ...))
        end

        local result = ...

        if type(result) == "string" then
            self.__class:api("answer_pre_checkout_query", {
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = result
            })
        elseif result == false then
            self.__class:api("answer_pre_checkout_query", {
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Sorry, it won't be possible to complete the payment for the item you selected. Please try again in the bot."})          
            })
        elseif result == true then
            self.__class:api("answer_pre_checkout_query", {
                pre_checkout_query_id = update_data.id,
                ok = true,
            })
            return true
        else
            self.__class:api("answer_pre_checkout_query", {
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
            })
            return catch(string.format("error on proccess pre checkout query: invalid return value"))
        end

    end)(pcall(transaction.transaction, this, unlist(action.args))) -- unlist(select("#", ...) > 0 and list(...) or action.args)

end

local function successful_payment(self, chat_id, language_code, update_data)

    local payload = update_data.successful_payment.invoice_payload

    if not payload:match("^luagram_transaction_%d+_%d+_%d+$") then
        return false
    end

    local user = self._users:get(chat_id)

    if not user then
        return false
    end

    local transaction = user.interactions[payload]

    if not transaction then
        return false
    end

    local this = self:chat(this._chat_id, this._language_code)

    this.status = function(self)
        return "successful_payment", self
    end

    this.say = function(self, ...)
        this:say(...)
        return self
    end

    this.send = function(self, ...)
        this:send(...)
        return self
    end

    pcall(transaction.transaction, this, unlist(action.args)) -- unlist(select("#", ...) > 0 and list(...) or action.args)

    return true
end

local function chat_id(update_data, update_type)
    if update_type == "callback_query" then
        return update_data.message.chat.id, update_data.message.from.language_code
    end
    return update_data.chat.id, update_data.from.language_code
end

function luagram:receive(update)
    -- obter o autor do dona do update
    -- verificar se o update não é um callback data query
    -- verificar se o update não é um comando
    -- verificar se o autor da menesagem posasui sessão aberta já
    -- caso não haja, ir para o entry point (se houver)
    -- caso não seja processado, enviar aos events

    local update_id, update_type, update_data

    assert(type(update) == "table", "invalid update")
    assert(not update.update_id, "invalid update")

    for key, value in pairs(update) do
        if key ~= "update_id" then
            update_type = key
            update_data = value
            break
        end
    end

    if not update_type or not update_data then
        error("invalid update")
    end

    local chat_id, language_code = chat_id(update_data, update_type)

    if update_type == "callback_query" then

        -- se retornar true, significa que foi handled já
        -- se retornar false ou nil, significa que não foi
        if callback_query(self, chat_id, update_data) == true then
            return
        end

        -- aqui deve -se verificar se o callback_query é o formato do luagram
        -- e responder de acordo
        --continuar para que seja enviado o entry point

        --luagram_event_(name) --> pesquisar por esse event
        --se houver: chamar e return

    elseif update_type == "shipping_query" then

        if shipping_query(self, chat_id, update_data) == true then
            return
        end

    elseif update_type == "pre_checkout_query" then

        if pre_checkout_query(self, chat_id, update_data) == true then
            return
        end

    elseif update_type == "message" and update_data.successful_payment  then

        if successful_payment(self, chat_id, update_data) == true then
            return
        end

    end

    local user = self._users:get(id)

    if not user then
        self._users:get(id, {
            interactions = {}
        })
    end

    local thread = user.thread

    if coroutine.status(thread.main) ~= "suspended" then
        user.thread = nil
    else

        local result
        local valid = true
        if thread.match then
            valid = false
            local _ = (function(ok, ...)
                if not ok then
                    thread.object:catch(string.format("error on match session thread (%s): %s", thread.object._name, ...))
                    return
                end
                if select("#", ...) > 0 then
                    valid = true
                    result = list(...)
                end
            end)(pcall(thread.main, update))
        end

        if valid then

            local ok, err = coroutine.resume(thread.main, unlist(result or list(update)))

            if not ok then
                thread.object:catch(string.format("error on execute main session thread (%s): %s", thread.object._name, err))
                return
            end

            if coroutine.status(thread.main) == "dead" then
                user.thread = nil
            end

        end

        return
    end


    --verificar se user não estiver com uma sessão ativa já (coroutine)
    --testar e continuar caso esteja

    --vertificar se não é comando
    if update_type == "message" then

        local text = update_data.text

        local command, space, payload = string.match(text, "^(/[a-zA-Z0-9_]+)(.?)(.*)$")

        if command and (space == " " or space == "") then

            if send(self, chat_id, command, payload) == true then
                -- se a função send retoirnar true significa que foi enviado com sucesso
                -- o comando existe
                return
            end

        end

    end

    --0 nada foi processado até aqui
    --chamar o entry point se haver

    if send(self, chat_id, language_code, "/start", false) == true then
        -- se a função send retoirnar true significa que foi enviado com sucesso
        -- entry point existe
        return
    end

    -- aqui deve ser chamado o evento pois não foi encontrado nada para processar

    if self._events[update_type] then
        if self._events[update_type](update) ~= false then
            return
        end
    end

    if self._events[true] then
        self._events[true](update)
        return
    end

    -- aqui deve chamar a função catch, pois não foi capaturado o update
    -- odefault da função catch é a função error
    if self._catch then
        self._catch("unhandled", update)
        return
    end

    -- aqui deve acontecer um erro

    --if update_type == "message" then ----? talvez não passe por esse if, pois pode ser um callback_query por exemplo

        -- verificar se é comando
        -- se for comando significa que é para "zerar" a sessão atual e iniciar nesse comando

        -- se não for comando verificar se há sessão atual
        -- se não houver: criar a sessão com base  echmar o entry point (Se houver)
        -- se já houver: continuar (se for thread) ou chmar o entry point (Se houver)
        


    --end

    -- se não haver entry point, deve ser chamado o evento

    return self
end

return setmetatable(luagram, {
  __call = function(self, ...)
      return self.new(...)
  end
})

