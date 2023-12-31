local unpack = table.unpack or unpack

local function list(...)
    return {["#"] = select("#", ...), ...}
end

local function unlist(value)
    return unpack(value, 1, value["#"])
end

local function id(self)
    self.__class._ids = self.__class._ids + 1
    return self.__class._ids
end

local http_provider, json_encoder, json_decoder

local function detect_env()
    if http_provider then
        return
    end
    local ok
    ok = pcall(_G.GetRedbeanVersion)
    if ok then
        http_provider = _G.Fetch
        json_encoder = _G.EncodeJson
        json_decoder = _G.DecodeJson
        return
    end
    local ngx_http
    ok, ngx_http = pcall(require, "lapis.nginx.http")
    if _G.ngx and ok then
        http_provider = function(url, options)
            return ngx_http.simple(url, options)
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
        if not options then
            options = {}
        end
        if options.body then
            options.source = ltn12.source.string(options.body)
        end
        options.sink = ltn12.sink.table(out)
        options.url = url
        local _, status, headers = http.request(options)
        local response = table.concat(out)
        return response, status, headers
    end
    local json
    ok, json = pcall(require, "cjson")
    if ok then
        json_encoder = json.encode
        json_decoder = json.decode
    else
        json = require("json")
        json_encoder = json.encode
        json_decoder = json.decode
    end
end

local function stdout(message)
    print(message)
    io.stdout:write("Luagram: ", os.date("!%Y-%m-%d %H:%M:%S GMT: "), message, "\n")
end

local function stderr(message)
    print("[Error] ", message)
    io.stderr:write("Luagram: ", os.date("!%Y-%m-%d %H:%M:%S GMT: "), "[Error] ", message, "\n")
end

local function request(self, url, options)
    local _http_provider = self.__class._http_provider or http_provider
    local response, response_status, headers = _http_provider(url, options)
    local response_headers
    if response_status == 200 and type(headers) == "table" then
        response_headers = {}
        for key, value in pairs(headers) do
            response_headers[string.lower(key)] = value
        end
    end
    return response, response_status, response_headers or headers
end

local function generate_boundary()
    local alpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    math.randomseed(os.time())
    local result = {}
    for _ = 1, 64 do
        local number = math.random(1, #alpha)
        result[#result + 1] = string.sub(alpha, number, number)
    end
    return table.concat(result)
end

local mimetypes = {
    png = "image/png",
    gif = "image/gif",
    jpeg = "image/jpg",
    jpg = "image/jpg",
    webp = "image/webp",
}

local function telegram(self, method, data, multipart)

    --multipart é nome da key que é o arquivo multipart
    --então se haver esse argumento é multipart
    --sendo multipart, ao passar por essa keu ele encoda como multipart
    local _json_encoder = self.__class._json_encoder or json_encoder
    local _json_decoder = self.__class._json_decoder or json_decoder
    local api = self.__class._api or "https://api.telegram.org/bot%s/%s"
    api = string.format(api, self.__class._token, string.gsub(method, "%W", ""))
    local headers, body
    if multipart then
        body = {}
        local boundary = generate_boundary()
        local name = assert(string.match(data[multipart], "([^/\\]+)$"), "invalid filename")
        local extension = string.lower(assert(string.match(name, "([^%.]+)$"), "no extension"))
        local mimetype = assert(mimetypes[extension], "invalid extension")
        local file = assert(io.open(data[multipart], "rb"))
        if file:seek("end") >= (1024 * 1024 * 50) then
            error("file is too big")
        end
        file:seek("set")
        local content = file:read("*a")
        file:close()
        for key, value in pairs(data) do
            body[#body + 1] = string.format("--%s\r\n", boundary)
            body[#body + 1] = string.format("Content-Disposition: form-data; name=%q", key)
            if key == multipart then
                body[#body + 1] = string.format("; filename=%q\r\n", name)
                body[#body + 1] = string.format("Content-Type: %s\r\n", mimetype)
                body[#body + 1] = "Content-Transfer-Encoding: binary\r\n\r\n"
                body[#body + 1] = content
            else
                body[#body + 1] = "\r\n\r\n"
                if type(value) == "table" then
                    body[#body + 1] = _json_encoder(value)
                else
                    body[#body + 1] = tostring(value)
                end
            end
            body[#body + 1] = "\r\n"
        end
        body[#body + 1] = string.format("--%s--\r\n\r\n", boundary)
        body = table.concat(body)
        headers = {
            ["content-type"] = string.format("multipart/form-data; boundary=%s", boundary),
            ["content-length"] = #body
        }
    else
        body = _json_encoder(data)
        headers = {
            ["content-type"] = "application/json",
            ["content-length"] = #body
        }
    end
    if self.__class._headers then
        for key, value in pairs(self.__class._headers) do
            headers[string.lower(key)] = value
        end
    end
    if not multipart then
        print("-->", method, body)
    else
        print("--> (multipart)", method)
    end
    local response, response_status, response_headers = request(self, api, {
        method = "POST",
        body = body,
        headers = headers
    })
    print("<--", response)
    local ok, result = pcall(_json_decoder, response)
    if ok and type(result) == "table" then
        if not result.ok then
            return false, string.format("%s: %s", result.error_code, result.description), response, response_status, response_headers
        end
        result = result.result
        if type(result) == "table" then
            result._response = response
        end
        return result, response, response_status, response_headers
    end
    return nil, result, response, response_status, response_headers
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
    local result = string.gsub(values[1], "(%%?)(%%[%-%+#%.%d]*[cdiouxXeEfgGqsaAp])%[(%w+)%]",
        function(prefix, specifier, name)
            if prefix == "%" then
                return string.format("%%%s[%s]", specifier, name)
            end
            if not values[name] then
                error("no key '" .. name .. "' for string found")
            end
            return string.format(specifier, (string.gsub(values[name], "%%", "%%%%")))
        end
    )
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

local function catch_error(...)
    local message = {}
    for index = 1, select("#", ...) do
        message[#message + 1] = tostring(select(index, ...))
    end
    stderr(debug.traceback(table.concat(message, "\n\n")))
end

-- se acontecer algum erro nas funções runtime do compose: catch do compose
-- caso contrario catch da instance

-- se acontecer algum erro na função main da session: catch da session
-- caso contrario catch da instance

local send_object

local function parse_compose(chat, compose, ...)
    -- é muito simples parsear uma mensagem
    --essa função de sex executada com pcall?

    print("entrou no compose parser@@@@@@")

    local users = chat.__class._users

    local user = users:get(chat._chat_id)

    if not user then
        compose:catch("user not found")
        return
    end

    local output = {}
    local texts = {}
    local buttons = {}
    local interactions = {}
    local row = {}
    local data = {}

    local media, media_type

    local title, description = {}, {}
    local prices = {}

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
    print("entrou no loop")
    while index <= #compose do
        local item = compose[index]
        if type(item) == "table" and item._type and item._indexed ~= compose._id then
            item._indexed = compose._id

            -- runtime
            if item._type == "run" then

                compose._runtime = index + 1
                local object, args = (function(ok, ...)
                    if not ok then
                        compose._catch(...)
                        return
                    end
                    return ..., list(select(2, ...))
                end)(pcall(item.run, compose, unlist(select("#", ...) > 0 and list(...) or compose._args)))
                compose._runtime = nil
                
                if object then
                    
                    if type(object) == "table" then
                        object = object._name
                    end

                    send_object(compose, chat._chat_id, chat._language_code, object, unlist(args["#"] > 0 and args or (select("#", ...) > 0 and list(...) or list())))

                    return false
                end

            -- texts
            elseif item._type == "text" then
                texts[#texts + 1] = escape(text(chat, item.value))
                close_tags()
            elseif item._type == "bold" then
                open_tags[#open_tags + 1] = "</b>"
                texts[#texts + 1] = "<b>"
                if item.value then
                    texts[#texts + 1] = escape(text(chat, item.value))
                    close_tags()
                end
            elseif item._type == "italic" then
                open_tags[#open_tags + 1] = "</i>"
                texts[#texts + 1] = "<i>"
                if item.value then
                    texts[#texts + 1] = escape(text(chat, item.value))
                    close_tags()
                end
            elseif item._type == "underline" then
                open_tags[#open_tags + 1] = "</u>"
                texts[#texts + 1] = "<u>"
                if item.value then
                    texts[#texts + 1] = escape(text(chat, item.value))
                    close_tags()
                end
            elseif item._type == "spoiler" then
                open_tags[#open_tags + 1] = "</tg-spoiler>"
                texts[#texts + 1] = "<tg-spoiler>"
                if item.value then
                    texts[#texts + 1] = escape(text(chat, item.value))
                    close_tags()
                end
            elseif item._type == "strike" then
                open_tags[#open_tags + 1] = "</s>"
                texts[#texts + 1] = "<s>"
                if item.value then
                    texts[#texts + 1] = escape(text(chat, item.value))
                    close_tags()
                end
            elseif item._type == "link" then
                close_tags()
                texts[#texts + 1] = '<a href="'
                texts[#texts + 1] = escape(item.url)
                texts[#texts + 1] = '">'
                texts[#texts + 1] = escape(text(chat, item.label))
                texts[#texts + 1] = "</a>"
            elseif item._type == "mention" then
                close_tags()
                texts[#texts + 1] = '<a href="'
                texts[#texts + 1] = escape(item.user)
                texts[#texts + 1] = '">'
                texts[#texts + 1] = escape(text(chat, item.name))
                texts[#texts + 1] = "</a>"
            elseif item._type == "emoji" then
                close_tags()
                texts[#texts + 1] = '<tg-emoji emoji-id="'
                texts[#texts + 1] = escape(item.emoji)
                texts[#texts + 1] = '">'
                texts[#texts + 1] = escape(text(chat, item.placeholder))
                texts[#texts + 1] = "</tg-emoji>"
            elseif item._type == "mono" then
                close_tags()
                texts[#texts + 1] = "<code>"
                texts[#texts + 1] = escape(text(chat, item.value))
                texts[#texts + 1] = "</code>"
            elseif item._type == "pre" then
                close_tags()
                texts[#texts + 1] = "<pre>"
                texts[#texts + 1] = escape(text(chat, item.value))
                texts[#texts + 1] = "</pre>"
            elseif item._type == "code" then
                close_tags()
                if item.language then
                    texts[#texts + 1] = '<pre><code class="language-'
                    texts[#texts + 1] = escape(item.language)
                    texts[#texts + 1] = '">'
                    texts[#texts + 1] = escape(text(chat, item.code))
                else
                    texts[#texts + 1] = "<pre><code>"
                    texts[#texts + 1] = escape(text(chat, item.code))
                end
                texts[#texts + 1] = "</code></pre>"
            elseif item._type == "line" then
                if item.value then
                    texts[#texts + 1] = "\n"
                    texts[#texts + 1] = escape(text(chat, item.value))
                end
                close_tags()
                texts[#texts + 1] = "\n"
            elseif item._type == "html" then
                close_tags()
                texts[#texts + 1] = text(chat, item.value)
            elseif item._type == "quote" then
                close_tags()
                texts[#texts + 1] = "\n"
                texts[#texts + 1] = escape(text(chat, item.value))
                texts[#texts + 1] = "\n"

            -- others
            elseif item._type == "media" then
                media = item.media
            elseif item._type == "title" then
                title[#title + 1] = text(chat, item.title)
            elseif item._type == "description" then
                description[#description + 1] = text(chat, item.description)
            elseif item._type == "price" then
                prices[#prices + 1] = {
                    label = text(chat, item.label),
                    amount = item.amount
                }
            elseif item._type == "data" then
                data[item.key] = item.value

            -- interactions
            elseif item._type == "button" then
                local event = string.format("Luagram_event_%s", item.event)
                if tonumber(item.arg) then
                    event = string.format("%s_%s", event, item.arg)
                end
                row[#row + 1] = {
                    text = text(chat, item.label),
                    callback_data = event
                }
            elseif item._type == "action" then
                if type(item.action) == "string" then
                    local action = item.action
                    item.action = function(_, ...)
                        return action, ...
                    end
                end
                local label = text(chat, item.label)
                local uuid = string.format("Luagram_action_%s_%s_%s", chat._chat_id, id(chat), os.time())
                interactions[#interactions + 1] = uuid
                local interaction = {
                    id = item.id,
                    compose = compose,
                    label = label,
                    action = item.action,
                    interactions = interactions,
                    args = item.args["#"] > 0 and item.args or (select("#", ...) > 0 and list(...) or compose._args)
                }
                user.interactions[uuid] = interaction
                row[#row + 1] = {
                    text = label,
                    callback_data = uuid
                }
            elseif item._type == "location" then
                row[#row + 1] = {
                    text = text(chat, item.label),
                    url = item.location
                }
            elseif item._type == "transaction" then
                if transaction then
                    error("transaction previously defined for this compose")
                end

                transaction = true

                local label = text(chat, item.label)

                if item.label ~= false then
                    table.insert(buttons, 1, {{
                        text = label,
                        pay = true
                    }})
                else
                    --não pode haver mais nenhum botão nesse caso
                    transaction_label = true
                end

                local uuid = string.format("Luagram_transaction_%s_%s_%s", chat._chat_id, id(chat), os.time())

                local interaction = {
                    id = item.id,
                    compose = compose,
                    label = label,
                    transaction = item.transaction,
                    interactions = interactions,
                    args = item.args["#"] > 0 and item.args or (select("#", ...) > 0 and list(...) or compose._args)
                }

                payload = uuid

                user.interactions[uuid] = interaction
                --se label for igual a false:
                --colocar esse botão no primeiro item da lista

            elseif item._type == "row" then
                if #row > 0 then
                    buttons[#buttons + 1] = row
                    row = {}
                end
            end
        end
        index = index + 1
    end
    close_tags()
    if #row > 0 then
        buttons[#buttons + 1] = row
    end

    if transaction and transaction_label and #buttons > 0 then
        error("add a label to transaction function to define actions in this compose")
    end

    if media then
        if string.match(string.lower(media), "^https?://[^%s]+$") then
            media_type = "url"
        elseif string.match(media, "%.") then
            media_type = "path"
            multipart = true
            print(":::::aqui")
        else
            media_type = "id"
        end
    end
print(":::::aqui",media_type)
    if transaction and media and media_type == "url" then
        if not data.photo_url then
            data.photo_url = media
            media = nil
        end
    elseif transaction and media then
        error("you can only define an url for transaction media")
    end

    if media and media_type == "id" then
        local response, err = chat.__class:get_file({
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

    elseif media and media_type == "url" then
        local response, status, headers = request(compose, media)

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

    elseif media and media_type == "path" then

        local extension = string.lower(assert(string.match(media, "([^%.]+)$"), "no extension"))

        if extension == "gif" then
            method = "animation"
        elseif extension == "png" or extension == "jpg" or extension == "jpeg" or extension == "webp" then
            method = "photo"
        else
            error(string.format("unknown media type: %s", media))
        end
print("::::::::::::::0",method)
    elseif media then
        error(string.format("unknown media type: %s", tostring(media)))
    end

    --lançar um erro aqui se for transactrion e não haver payment_successfully event
    --se for transaction colocar pra mostrar recibo e mdata
    --olhar botgram

    --dependendo do método da mensagem e havendo multipart
    --colocar o nome do field aqui

    if transaction then
        if media then
            output.photo_url = media
        end

        method = "invoice"
        output.title = table.concat(title)
        output.description = table.concat(description)
        output.payload = payload
        output.start_parameter = payload
        output.protect_content = true
        output.currency = chat.__class._transaction_currency
        output.provider_token = chat.__class._transaction_provider_token
        output.prices = prices
    else
        
        data.parse_mode = "HTML"

        if method == "animation" then
            if media then
                output.animation = media
                if multipart then
                    compose._multipart = "animation"
                end
            end
            output.caption = table.concat(texts)
        elseif method == "photo" then
            if media then
                output.photo = media
                if multipart then
                    compose._multipart = "photo"
                end
            end
            output.caption = table.concat(texts)
        else
            output.text = table.concat(texts)
        end

    end

    output.chat_id = chat._chat_id

    if #buttons > 0 then
        output.reply_markup = {
            inline_keyboard	= buttons
        }
    end


    --aqui deve processar de acordo com o tipo da mensagem
    --se for transaction:
    --deve checar se há os campos certos
    --se for media deve informar o field certo de acordo
    --se a media for um io.open
    --deve enviar via multipart

    for key, value in pairs(data) do
        print("adicionou", key, value)
        output[key] = value
    end

    compose._transaction = transaction
    compose._media = media
    compose._method = method
    compose._output = output

    return compose
end

send_object = function(self, chat_id, language_code, name, ...)

    local users = self.__class._users
    local objects = self.__class._objects

    local user = users:get(chat_id)

    if not user then
        users:set(chat_id, {
            created_at = os.time(),
            interactions = {}
        })
        user = users:get(chat_id)
    end

    local object = objects[name]

    if not object then
        error(string.format("object not found: %s", name))
    end

    local chat = self.__class:chat(chat_id, language_code)

    if object._type == "compose" then

        local this = object:clone()

        this._chat_id = chat_id
        this._language_code = language_code

        this.send = function(self, ...)
            chat:send(...)
            return self
        end

        this.print = function(self, ...)
            chat:print(...)
            return self
        end

        local result, err = parse_compose(chat, this, ...)

        if result then

            if object._predispatch then
                local parsed_result = object._predispatch(result)
                if type(parsed_result) == "table" then
                    result = parsed_result
                end
            end

            local response, err

            if result._method == "animation" then
                response, err = self.__class:send_animation(result._output, result._multipart)
            elseif result._method == "photo" then
                response, err = self.__class:send_photo(result._output, result._multipart)
            elseif result._method == "message" then
                response, err = self.__class:send_message(result._output, result._multipart)
            elseif result._method == "invoice" then
                response, err = self.__class:send_invoice(result._output, result._multipart)
            else
                error("invalid method")
            end

            if not response then
                error(err)
            end

            if object._dispatch then
                object._dispatch(response)
            end

        elseif result == nil then
            error(string.format("parser error: %s", err))
        end

    elseif object._type == "session" then

        -- aqui deve-se criar uma nova sessão
        --chmar a nova sessão

        if not object._main then
            error(string.format("undefined main session thread: %s", name))
            return
        end

        user.thread = {}

        local thread = user.thread

        chat.await =  function(_, match)
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
            object._catch(string.format("error on execute main session thread: %s", err))
            return
        end

        if coroutine.status(thread.main) == "dead" then
            user.thread = nil
        end

    else

        error(string.format("undefined object type: %s", name))

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

    --se compose: parsear um novo clone da mensage
    --(criar metodo: chat, send)
    --enviar

    -- session: criar uma sessao nova

    --retirnar true caso sucesso

end

local addons = {}

addons.compose = function(self)

    self:class("compose", function(self, name, ...)
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

        self._type = "compose"
        self._id = id(self)
        self._args = list(...)
        self:catch(catch_error)
        self._name = name
        if name ~= false then
            self.__class._objects[name] = self
        end
    end, function(self, key)
        local value = rawget(getmetatable(self), key)
        if value == nil and type(key) == "string" then
            local _chat_id = rawget(self, "_chat_id")
            if _chat_id and not string.match(key, "^_") and not string.match(key, "^on_%w+$") then
                return function(self, data, multipart)
                    if type(data) == "table" and data.chat_id == nil then
                        data.chat_id = _chat_id
                    end
                    return telegram(self, key, data, multipart)
                end
            end
        end
        return value
    end)

    local compose = self.compose

    compose.clone = function(self)
        local clone = self.__class:compose(false)
        for key, value in pairs(self) do
            if key ~= "_id" and key ~= "__class" then
                if type(value) == "table" and not value._runtime then
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
        if not clone._origin then
            clone._origin = self
        end
        clone._chat_id = nil
        clone._language_code = nil
        return clone
    end

    local function insert(self, index, data)
        if not index then
            if self._runtime then
                data._runtime = true
                for k,v in pairs(data) do print(k,v) end
                table.insert(self, self._runtime, data)
                self._runtime = self._runtime + 1
            else
                table.insert(self, data)
            end
        else
            table.insert(self, index, data)
        end
    end

    local function simple(_type, arg1) -- luacheck: ignore
        return function(self, ...)
            local index, value1 = ...
            local _index
            if type(index) == "number" and select("#", ...) > 1 then
                _index = index
            else
                value1 = index
            end
            insert(self, _index, {
                _type = _type,
                [arg1] = value1
            })
            return self
        end
    end

    local function multiple(_type, arg1, arg2) -- luacheck: ignore
        return function(self, ...)
            local index, value1, value2 = ...
            local _index
            if type(index) == "number" and select("#", ...) > 1 then
                _index = index
            else
                value2 = value1
                value1 = index
            end
            insert(self, _index, {
                _type = _type,
                [arg1] = value1,
                [arg2] = value2
            })
            return self
        end
    end

    local items = {
        "text", "bold", "italic", "underline", "spoiler", "strike", "mono", "pre", "html", "quote"
    }

    for index = 1, #items do
        local _type = items[index]
        compose[_type] = simple(_type, "value")
    end

    compose.run = simple("run", "run")

    compose.link = function(self, ...)
        local index, label, url = ...
        local _index
        if type(index) == "number" and select("#", ...) > 1 then
            _index = index
        else
            url = label
            label = index
        end
        if url == nil then
            url = label
        end
        insert(self, _index, {
            _type = "link",
            url = url,
            label = label,
        })
        return self
    end

    compose.mention = function(self, ...)
        local index, user, name = ...
        local _index
        if type(index) == "number" and select("#", ...) > 1 then
            _index = index
        else
            name = user
            user = index
        end
        if tonumber(user) then
            user = string.format("tg://user?id=%s", user)
        else
            if not name then
                name = user
            end
            user = string.format("https://t.me/%s", user)
        end
        insert(self, _index, {
            _type = "mention",
            user = user,
            name = name,
        })
        return self
    end

    compose.emoji = multiple("emoji", "emoji", "placeholder")

    compose.code = function(self, ...)
        local index, language, code = ...
        local _index
        if type(index) == "number" and select("#", ...) > 1 then
            _index = index
        else
            code = language
            language = index
        end
        if code == nil then
            code = language
            language = nil
        end
        insert(self, _index, {
            _type = "code",
            code = code,
            language = language,
        })
        return self
    end

    compose.line = function(self, ...)
        local index, line = ...
        local _index
        if type(index) == "number" then
            _index = index
        else
            line = index
        end
        insert(self, _index, {
            _type = "line",
            value = line
        })
        return self
    end

    compose.media = simple("media", "media")

    compose.title = simple("title", "title")

    compose.description = simple("description", "description")

    compose.price = multiple("price", "label", "amount")

    compose.data = multiple("data", "key", "value")

    compose.button = function(self, ...)
        local index, label, event, arg = ...
        local _index
        if type(index) == "number" and select("#", ...) > 1 then
            _index = index
        else
            arg = event
            event = label
            label = index
        end
        if #event > 15 or string.match(event, "%W") then
            error(string.format("invalid event name: %s", event))
        end
        if arg then
            arg = tonumber(arg)
            if not arg then
                error(string.format("invalid argument: %s", arg))
            end
        end
        insert(self, _index, {
            _type = "button",
            label = label,
            event = event,
            arg = arg
        })
        return self
    end

    compose.action = function(self, ...)
        local index, label, action = ...
        local args
        local _index
        if type(index) == "number" and select("#", ...) > 1 then
            _index = index
            args = list(select(4, ...))
        else
            action = label
            label = index
            args = list(select(3, ...))
        end
        insert(self, _index, {
            _type = "action",
            id = id(self),
            label = label,
            action = action,
            args = args
        })
        return self
    end

    compose.location = function(self, ...)
        local index, label, location = ...
        local _index
        if type(index) == "number" and select("#", ...) > 1 then
            _index = index
        else
            location = label
            label = index
        end
        insert(self, _index, {
            _type = "location",
            label = label,
            location = location
        })
        return self
    end

    compose.transaction = function(self, ...)
        local index, label, transaction = ...
        local args
        local _index
        if type(index) == "number" and select("#", ...) > 1 then
            _index = index
        else
            transaction = label
            label = index
        end
        if type(label) == "function" then
            transaction = label
            label = false
            if _index then
                args = list(select(3, ...))
            else
                args = list(select(2, ...))
            end
        else
            if _index then
                args = list(select(4, ...))
            else
                args = list(select(3, ...))
            end
        end
        insert(self, _index, {
            _type = "transaction",
            id = id(self),
            label = label,
            transaction = transaction,
            args = args
        })
        return self
    end

    compose.row = function(self, ...)
        local index = ...
        local _index
        if type(index) == "number" then
            _index = index
        end
        insert(self, _index, {
            _type = "row"
        })
        return self
    end

    compose.dispatch = function(self, dispatch, before)
        if before then
            self._predispatch = dispatch
        else
            self._dispatch = dispatch
        end
        return self
    end

    compose.catch = function(self, catch)
        self._catch = function(...)
            catch(self._name, ...)
        end
        return self
    end

    return self
end

addons.session = function(self)

    self:class("session", function(self, name, ...)
        if name == nil then
            name = "/start"
        end

        self._type = "session"
        self._id = id(self)
        self._name = name
        self._args = list(...)
        self:catch(catch_error)
        self.__class._objects[name] = self
    end)

    local session = self.session

    session.main = function(self, main)
        self._main = main
        return self
    end

    session.catch = function(self, catch)
        self._catch = function(...)
            catch("(", self._name, ") ", ...)
        end
        return self
    end

    return self
end

addons.chat = function(self)

    self:class("chat", function(self, chat_id, language_code)
        self._type = "chat"
        self._chat_id = chat_id
        self._language_code = language_code
    end, function(self, key)
        local value = rawget(getmetatable(self), key)
        if value == nil and type(key) == "string" then
            if not string.match(key, "^_") and not string.match(key, "^on_%w+$") then
                return function(self, data, multipart)
                    if type(data) == "table" and data.chat_id == nil then
                        data.chat_id = rawget(self, "_chat_id")
                    end
                    return telegram(self, key, data, multipart)
                end
            end
        end
        return value
    end)

    local chat = self.chat

    chat.send = function(self, name, ...)
        send_object(self, self._chat_id, self._language_code, name, ...)
        return self
    end

    chat.print = function(self, ...)
        local texts = {}
        for index = 1, select("#", ...) do
            texts[#texts + 1] = text(self, (select(index, ...)))
        end
        self.__class:send_message({
            chat_id = self._chat_id,
            text = table.concat(texts, "\n")
        })
        return self
    end

    chat.text = function(self, value)
        return text(self, value)
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

local Luagram = {}

function Luagram.new(options)
    local self = setmetatable({}, Luagram)

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
    self._users = lru.new(options.cache or 1024)
    self._catch = catch_error
    self._http_provider = options.http_provider
    self._json_encoder = options.json_encoder
    self._json_decoder = options.json_decoder
    self.__class = self

    self._token = options.token
    
    if options.transactions then
        self._transaction_report_to = options.transactions.report_to
        self._transaction_currency = options.transactions.currency
        self._transaction_provider_token = options.transactions.provider_token
    end

    self:addon("compose")
    self:addon("session")
    self:addon("chat")

    self:on_unhandled(stdout)

    if not self._http_provider and not http_provider then
        detect_env()
    end

    return self
end

function Luagram:class(name, new, index)
    local class = {}
    class.__index = index or class
    self[name] = setmetatable({}, {
        __call = function(_, base, ...)
            local self = setmetatable({}, class)
            self.__name = name
            self.__class = base
            return (new and new(self, ...)) or self
        end,
        __index = class,
        __newindex = class
    })
    return self
end

function Luagram:__index(key)
    local value = rawget(Luagram, key)
    if value == nil and type(key) == "string" then
        local event = string.match(key, "^on_(%w+)$")
        if event then
            return function(self, callback)
                self._events[event] = callback
                return self
            end
        elseif not string.match(key, "^_") then
            return function(self, data, multipart)
                return telegram(self, key, data, multipart)
            end
        end
    end
    return value
end

function Luagram:addon(name, ...)
    if addons[name] then
        return addons[name](self, ...) or self
    end
    local path = package.path
    package.path = "./addons/?.lua;" .. path
    local ok, addon = pcall(require, name)
    package.path = path
    if not ok then
        error("addon '" .. name .. "' not found")
    end
    return addon(self, ...) or self
end

function Luagram:locales(locales)

    if type(locales) == "string" then
        local path = package.path
        package.path = "./locales/?.lua;" .. path
        local ok, addon = pcall(require, locales)
        package.path = path
        if not ok then
            error("addon '" .. locales .. "' not found")
        end
        locales = addon
    end

    self._locales = locales
    return self
end

function Luagram:on(callback)
    self._events[true] = callback
    return self
end

local function callback_query(self, chat_id, language_code, update_data)

    local data = update_data.data

    if not data:match("^Luagram_action_%d+_%d+_%d+$") then
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
        self.__class:answer_callback_query(answer)
        return true
    end

    action.lock = true



    -- necessáriorealizar uma copia da mensagem original
    -- essa mensagem é passada a função
    -- como realizar uma cópia de maneira adequada?
    -- criando  uma classe (talvez um argumento false)
    -- então copiar todos os itens do original e jogar no item novo novamente
    -- provavelmente a melhor maneira

    local this = action.compose:clone()

    this._update_data = update_data
    this._update_type = "callback_query"
    this._language_code = language_code
    this._chat_id = chat_id

    local chat = self:chat(chat_id, language_code)

    this.print = function(self, ...)
        chat:print(...)
        return self
    end

    this.send = function(self, ...)
        chat:send(...)
        return self
    end

    this.source = function(self)
        return self._update_data, self._update_type
    end

    this.this = function(self)
        for index = 1, #self do
            print(action.id)
            print(self[index].id)
            if type(self[index]) == "table" and self[index]._type == "action" and self[index].id == action.id then
                self[index].index = index
                return self[index]
            end
        end
        return nil
    end

    this.clear = function(self, _type) -- luacheck: ignore
        local buttons = {
            button = true, action = true, location = true, transaction = true, row = true
        }
        local texts ={
            text = true, bold = true, italic = true, underline = true, spoiler = true, strike = true, link = true, mention = true, mono = true, pre = true, line = true, html = true, quote = true
        }
        for index = 1, #self do
            local item = self[index]
            if _type == "buttons" and type(item) == "table" then
                if buttons[item._type] then
                    self[index] = true
                end
            elseif _type == "texts" and type(item) == "table" then
                if texts[item._type] then
                    self[index] = true
                end
            end
        end
                print("#################################")
        for k,v in pairs(self) do
            print(k,v)
            if type(v) =="table" then
                for k2,v2 in pairs(v) do
                    print(" "," ",k2, v2)
                end
            end
        end
        return self
    end

    this.notify = function(self, value, alert)
        if not answer.text then
            answer.text = {}
        end
        if alert then
            answer.show_alert = true
        end
        answer.text[#answer.text + 1] = text(self, value)
        return self
    end

    this.redirect = function(self, url)
        answer.url = url
        return self
    end

    local _ = (function(ok, result, ...)

        if not ok then
            action.compose._catch(result)
            return
        end

        if result == true then
            this = self.compose.clone(action.compose._origin)
        elseif result == false then
            this:clear("buttons")
        elseif type(result) == "string" then
            local object = self.__class._objects[result]
            if object then
                if object._type == "compose" then
                    this = self.compose.clone(object)
                elseif  object._type == "session" then
                    for _, value in pairs(action.interactions) do
                        user.interactions[value] = nil
                    end
                    self.__class:edit_message_reply_markup({
                        chat_id = chat_id,
                        message_id = update_data.message.message_id
                    })
                    send_object(self, chat_id, language_code, object._name, unlist(select("#", ...) > 0 and list(...) or action.args))
                    return
                else
                   error("invalid object")
                end
            else
                error("object not found")
            end
        elseif type(result) == "table" and result._type == "session" then
            for _, value in pairs(action.interactions) do
                user.interactions[value] = nil
            end
            self.__class:edit_message_reply_markup({
                chat_id = chat_id,
                message_id = update_data.message.message_id
            })
            send_object(self, chat_id, language_code, result._name, unlist(select("#", ...) > 0 and list(...) or action.args))
            return
        elseif type(result) == "table" and result._type == "compose" then
            this = result
        elseif result == nil then
            return
        else
            error("invalid result")
        end

        if action.compose._transaction then

            for _, value in pairs(action.interactions) do
                user.interactions[value] = nil
            end
            local ok, message = self.__class:edit_message_reply_markup({
                chat_id = chat_id,
                message_id = update_data.message.message_id
            })
            if not ok then
                action.compose._catch(message)
                return
            end
            
            send_object(self, chat_id, language_code, this._name, unlist(select("#", ...) > 0 and list(...) or action.args))

            return
        end

        if action.compose._media then
            if not this._media then
                this._media = action.compose._media
            end

            if action.compose._media ~= this._media then
                local ok, message = self.__class:edit_message_media({
                    chat_id = chat_id,
                    message_id = update_data.message.message_id,
                    media = this._media
                })
                if not ok then
                    action.compose._catch(message)
                    return
                end
            end

        elseif not action.compose._media and this._media then
            --remover os botões da mensagem antiga
            --enviar uma nova mensagem
            for _, value in pairs(action.interactions) do
                user.interactions[value] = nil
            end
            local ok, message = self.__class:edit_message_reply_markup({
                chat_id = chat_id,
                message_id = update_data.message.message_id
            })
            if not ok then
                action.compose._catch(message)
                return
            end
            send_object(self, chat_id, language_code, this._name, unlist(select("#", ...) > 0 and list(...) or action.args))

            return
        end

        for _, value in pairs(action.interactions) do
            user.interactions[value] = nil
        end

--        print("antes")
--        for k,v in pairs(this) do
--            print(k,v)
--            if type(v) =="table" then
--                for k2,v2 in pairs(v) do
--                    print(" "," ",k2, v2)
--                end
--            end
--        end

        local compose = parse_compose(chat, this, unlist(select("#", ...) > 0 and list(...) or action.args))

--        print("depois")
--        for k,v in pairs(compose) do
--            print(k,v)
--            if type(v) =="table" then
--                for k2,v2 in pairs(v) do
--                    print(" "," ",k2, v2)
--                enn
--            end
--        end

        local ok, message

        if not compose then
            action.compose._catch("parser error")
            return
        end

        if this._method == "message" then
            ok, message = self.__class:edit_message_text({
                chat_id = chat_id,
                message_id = update_data.message.message_id,
                text = compose._output.text,
                parse_mode = compose._output.parse_mode,
                reply_markup = compose._output.reply_markup
            })
        else
            ok, message = self.__class:edit_message_caption({
                chat_id = chat_id,
                message_id = update_data.message.message_id,
                caption = compose._output.caption,
                parse_mode = compose._output.parse_mode,
                reply_markup = compose._output.reply_markup
            })
        end

        if not ok then
            action.compose._catch(message)
        end

    end)(pcall(action.action, this, unlist(action.args)))

    action.lock = false

    if type(answer.text) == "table" then
        answer.text = table.concat(answer.text)
    end
    answer.callback_query_id = update_data.id
    self.__class:answer_callback_query(answer)

    return true
end

local function shipping_query(self, chat_id, language_code, update_data)

    local payload = update_data.invoice_payload

    if not payload:match("^Luagram_transaction_%d+_%d+_%d+$") then
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

    local catch = transaction.compose._catch

    local this = self:chat(chat_id, language_code)

    this.status = function()
        return "shipping"
    end

    this.source = function()
        return update_data, "shipping_query"
    end

    local _ = (function(ok, ...)

        if not ok then
            self.__class:answer_shipping_query({
                shipping_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
            })
            catch(string.format("error on proccess shipping query: %s", ...))
            return
        end

        local result = ...

        if type(result) == "string" then
            self.__class:answer_shipping_query({
                shipping_query_id = update_data.id,
                ok = false,
                error_message = text(self, result)
            })
            return
        elseif result == false then
            self.__class:answer_shipping_query({
                shipping_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Sorry, delivery to your desired address is unavailable."})
            })
            return
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
                    self.__class:answer_shipping_query({
                        shipping_query_id = update_data.id,
                        ok = false,
                        error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
                    })
                    catch(string.format("error on proccess shipping query: invalid return value"))
                    return
                end
            end
            self.__class:answer_shipping_query({
                shipping_query_id = update_data.id,
                ok = true,
                shipping_options = options
            })
            return
        end
        
        self.__class:answer_shipping_query({
            shipping_query_id = update_data.id,
            ok = false,
            error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
        })
        catch(string.format("error on proccess shipping query: invalid return value"))

    end)(pcall(transaction.transaction, this, unlist(transaction.args)))

    return true

end

local function pre_checkout_query(self, chat_id, language_code, update_data)

    local payload = update_data.invoice_payload

    if not payload:match("^Luagram_transaction_%d+_%d+_%d+$") then
        return false
    end

    local user = self._users:get(chat_id)

    if not user then
        return false
    end

    local transaction = user.interactions[payload]

    local catch = transaction.compose._catch

    if not transaction then
        return false
    end

    local this = self:chat(chat_id, language_code)

    this.status = function()
        return "review"
    end

    this.source = function()
        return update_data, "pre_checkout_query"
    end

    local _ = (function(ok, ...)

        if not ok then
            self.__class:answer_pre_checkout_query({
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
            })
            catch(string.format("error on proccess pre checkout query: %s", ...))
            return
        end

        local result = ...

        if type(result) == "string" then
            self.__class:answer_pre_checkout_query({
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = text(self, result)
            })
            return
        elseif result == false then
            self.__class:answer_pre_checkout_query({
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Sorry, it won't be possible to complete the payment for the item you selected. Please try again in the bot."})
            })
            return
        elseif result == true then
            self.__class:answer_pre_checkout_query({
                pre_checkout_query_id = update_data.id,
                ok = true
            })
            return
        end
        
        self.__class:answer_pre_checkout_query({
            pre_checkout_query_id = update_data.id,
            ok = false,
            error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
        })
        catch(string.format("error on proccess pre checkout query: invalid return value"))

    end)(pcall(transaction.transaction, this, unlist(transaction.args)))

    return true

end

local function successful_payment(self, chat_id, language_code, update_data)

    local payload = update_data.successful_payment.invoice_payload

    if not payload:match("^Luagram_transaction_%d+_%d+_%d+$") then
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

    local this = self:chat(chat_id, language_code)

    this.status = function()
        return "complete"
    end

    this.source = function()
        return update_data, "successful_payment"
    end

    pcall(transaction.transaction, this, unlist(transaction.args))

    return true
end

local function chat_id(update_data, update_type)
    if update_type == "callback_query" then
        return update_data.message.chat.id, update_data.message.from.language_code
    elseif update_type == "pre_checkout_query" or update_type == "shipping_query" then
        return update_data.from.id, update_data.from.language_code
    end
    return assert(update_data.chat.id, "chat_id not found"), update_data.from.language_code
end

local function parse_update(self, update)
    local update_type, update_data

    assert(type(update) == "table", "invalid update")
    assert(update.update_id, "invalid update")

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
    
    local user = self._users:get(chat_id)

    if update_type == "callback_query" then

        -- se retornar true, significa que foi handled já
        -- se retornar false ou nil, significa que não foi
        if callback_query(self, chat_id, language_code, update_data) == true then
            return self
        end

        local event, arg = string.match(update_data.data, "^Luagram_event_(%w+)_?(%d*)$")

        if event then

            print("é evento", event, arg, type(arg))

            if arg == "" then
                arg = nil
            else
                arg = tonumber(arg)
            end

            self.__class:answer_callback_query({
                callback_query_id = update_data.id
            })


            if self._events[event] and self._events[event](update_data, arg) ~= false then
                print("aqui1")
                return self
            end

            if self._events[true] then
                print("aqui2")
                self._events[true](update_data, arg)
                return self
            end

            if self._events.unhandled then
                self._events.unhandled(update._response)
                return self
            end

            print("aqui3")
            error(string.format("unhandled update: %s", update._response))
            return self

        end

        local time = string.match(update_data.data, "^Luagram_action_%d+_%d+_(%d+)$")
        if time and (not user or tonumber(time) < user.created_at) then
            self.__class:answer_callback_query({
                callback_query_id = update_data.id,
                text = text(self:chat(chat_id, language_code), {"Welcome back! This message is outdated. Let's start over!"})
            })
            if send_object(self, chat_id, language_code, "/start") == true then
                return self
            end
        end

        -- aqui deve -se verificar se o callback_query é o formato do luagram
        -- e responder de acordo
        --continuar para que seja enviado o entry point

        --luagram_event_(name) --> pesquisar por esse event
        --se houver: chamar e return

    elseif update_type == "shipping_query" then

        if shipping_query(self, chat_id, language_code, update_data) == true then
            return self
        end

        if string.match(update_data.invoice_payload, "^Luagram_transaction_%d+_%d+_%d+$") then
            self.__class:answer_shipping_query({
                shipping_query_id = update_data.id,
                ok = false,
                error_message = text(self:chat(chat_id, language_code), {"Unfortunately, there was an issue while completing this payment."})
            })
            return self
        end

    elseif update_type == "pre_checkout_query" then

        if pre_checkout_query(self, chat_id, language_code, update_data) == true then
            return self
        end

        if string.match(update_data.invoice_payload, "^Luagram_transaction_%d+_%d+_%d+$") then
            self.__class:answer_pre_checkout_query({
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = text(self:chat(chat_id, language_code), {"Unfortunately, it wasn't possible to complete this payment. Please start the process again in the bot."})
            })
            return self
        end

    elseif update_type == "message" and update_data.successful_payment  then

        if successful_payment(self, chat_id, language_code, update_data) == true then
            return self
        end

        if string.match(update_data.invoice_payload, "^Luagram_transaction_%d+_%d+_%d+$") then
            return self
        end

    end

    if not user then
        print("$$$$$$$$$$$$$$$$$ criando user")
        self._users:set(chat_id, {
            created_at = os.time(),
            interactions = {}
        })
        user = self._users:get(chat_id)
    end

    local thread = user.thread

    if thread then
        
        print("!!!!!!!!!!!!!!!!é thread", coroutine.status(thread.main))
        
        if coroutine.status(thread.main) ~= "suspended" then
            user.thread = nil
        else

            local result
            local valid = true
            if thread.match then
                valid = false
                local _ = (function(ok, ...)
                    if not ok then
                        thread.object._catch(string.format("error on match session thread: %s", ...))
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
                    thread.object._catch(string.format("error on execute main session thread : %s", err))
                    return self
                end

                if coroutine.status(thread.main) == "dead" then
                    user.thread = nil
                end

            end

            return self
        end
    end


    --verificar se user não estiver com uma sessão ativa já (coroutine)
    --testar e continuar caso esteja

    --vertificar se não é comando
    if update_type == "message" then

        local text = update_data.text

        local command, space, payload = string.match(text, "^(/[a-zA-Z0-9_]+)(.?)(.*)$")

        if command then
            
            if space == " " and payload ~= "" then
                if send_object(self, chat_id, language_code, command, payload) == true then
                    return self
                end
            else
                if send_object(self, chat_id, language_code, command) == true then
                    return self
                end
            end

        end


        --0 nada foi processado até aqui
        --chamar o entry point se haver

        if send_object(self, chat_id, language_code, "/start") == true then
            -- se a função send retoirnar true significa que foi enviado com sucesso
            -- entry point existe
            return self
        end

    end

    -- aqui deve ser chamado o evento pois não foi encontrado nada para processar

    if self._events[update_type] then
        if self._events[update_type](update) ~= false then
            return self
        end
    end

    if self._events[true] then
        self._events[true](update)
        return self
    end

    if self._events.unhandled then
        self._events.unhandled(update._response)
        return self
    end

    -- aqui deve chamar a função catch, pois não foi capaturado o update
    -- odefault da função catch é a função error

    error(string.format("unhandled update: %s", update._response))
end

function Luagram:update(update)
    -- obter o autor do dona do update
    -- verificar se o update não é um callback data query
    -- verificar se o update não é um comando
    -- verificar se o autor da menesagem posasui sessão aberta já
    -- caso não haja, ir para o entry point (se houver)
    -- caso não seja processado, enviar aos events


    xpcall(function()

        if type(update) ~= "table" then
            error(string.format("invalid update: %s", update))
        end

        parse_update(self, update)
    end, self._catch)

    -- aqui deve acontecer um erro

    --if update_type == "compose" then ----? talvez não passe por esse if, pois pode ser um callback_query por exemplo

        -- verificar se é comando
        -- se for comando significa que é para "zerar" a sessão atual e iniciar nesse comando

        -- se não for comando verificar se há sessão atual
        -- se não houver: criar a sessão com base  echmar o entry point (Se houver)
        -- se já houver: continuar (se for thread) ou chmar o entry point (Se houver)



    --end

    -- se não haver entry point, deve ser chamado o evento

    return self
end

function Luagram:updates(stop)
    if stop == false then
        self._stop = true
        return self
    end
    local offset
    while true do
        if self._stop then
            self._stop = nil
            break
        end
        local result, err = self:get_updates({
            offset = offset
        })
        if result then
            for index = 1, #result do
                local update = result[index]
                update._response = result._response
                offset = update.update_id + 1
                self:update(update)
            end
        else
            self._catch(err)
        end
    end
    return self
end

return setmetatable(Luagram, {
    __call = function(self, ...)
        return self.new(...)
    end
})
