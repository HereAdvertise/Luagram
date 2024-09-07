-- (c) 2023-2024 HereAdvertise. MIT Licensed.

local unpack = table.unpack or unpack

local function list(...)
    return {["#"] = select("#", ...), ...}
end

local function unlist(value)
    return unpack(value, 1, value["#"])
end

local function id(self)
    self.__super._ids = self.__super._ids + 1
    return self.__super._ids
end

local function stdout(message)
    io.stdout:write("(Luagram) ", os.date("!%Y-%m-%d %H:%M:%S GMT: "), tostring(message), "\n")
    io.stdout:flush()
end

local function stderr(message)
    io.stderr:write("(Luagram) ", os.date("!%Y-%m-%d %H:%M:%S GMT: "), "[Error] ", tostring(message), "\n")
    io.stderr:flush()
end

local function request(self, url, options)
    local response, response_status, headers = self.__super._http_provider(url, options)
    local response_headers
    if response_status == 200 and type(headers) == "table" then
        response_headers = {}
        for key, value in pairs(headers) do
            response_headers[string.lower(key)] = value
        end
    end
    return response, response_status, response_headers or headers
end

local function assert_level(level, ...)
    if not select(1, ...) then
        return error(setmetatable({select(2, ...)}, {__tostring = function(self) return self[1] or "assertion failed!" end}), level)
    end
    return ...
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
    mp4 = "video/mp4",
}

local function telegram(self, method, data, multipart, tries)
    local api = self.__super._api or "https://api.telegram.org/bot%s/%s"
    tries = tries or 0
    api = string.format(api, self.__super._token, string.gsub(method, "%W", ""))
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
                    body[#body + 1] = self.__super._json_encoder(value)
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
        body = self.__super._json_encoder(data)
        headers = {
            ["content-type"] = "application/json",
            ["content-length"] = #body
        }
    end
    if self.__super._headers then
        for key, value in pairs(self.__super._headers) do
            headers[string.lower(key)] = value
        end
    end
    if self.__super._debug then
        if not multipart then
            stdout(string.format("--> %s %s", tostring(method), data and tostring(body) or "{}"))
        else
            stdout(string.format("--> %s (multipart: %s)", tostring(method), tostring(multipart)))
        end
    end
    local response, response_status, response_headers = request(self, api, {
        method = "POST",
        body = body,
        headers = headers
    })
    if self.__super._debug then
        stdout(string.format("<-- %s %s (status: %s)", tostring(method), tostring(response), tostring(response_status)))
    end
    local ok, result, err = pcall(self.__super._json_decoder, response)
    if ok and type(result) == "table" and result.ok then
        result = result.result
        if type(result) == "table" then
            result._response = response
        end
        pcall(self._sleep_fn, .05)
        return result, response, response_status, response_headers
    elseif ok and type(result) == "table" then
        if type(result.parameters) == "table" and result.parameters.migrate_to_chat_id then
            stderr(string.format("chat_id migrated to %s", tostring(result.parameters.migrate_to_chat_id)))
        end
        if tries == 0 and type(result.parameters) == "table" and type(result.parameters.retry_after) == "number" then
            pcall(self._sleep_fn, result.parameters.retry_after)
            return telegram(self, method, data, multipart, tries + 1)
        end
        pcall(self._sleep_fn, .05)
        return false, string.format("%s (%s) %s", tostring(method), result.error_code or "?", result.description or ""), response, response_status, response_headers
    end
    if tries == 0 then
        pcall(self._sleep_fn, 1)
        return telegram(self, method, data, multipart, tries + 1)
    end
    return nil, string.format("%s (%s) %s", tostring(method), response_status or "?", tostring(result or err or response or "")), response, response_status, response_headers
end

local function escape_html(text)
    return (string.gsub(tostring(text), '[<>&"]', {
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ["&"] = "&amp;",
        ['"'] = "&quot;"
    }))
end

local function escape_path(text)
    return (string.gsub(text, "[^%w%+]", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function locale(self, value, number)
    local locales = self.__super._locales
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
    local result = string.gsub(values[1], "(%%?)(%%[%-%+#%.%d]*[cdiouxXeEfgGqsaAp])%[(.-)%]",
        function(prefix, specifier, name)
            if prefix == "%" then
                return string.format("%%%s[%s]", specifier, name)
            end
            if not values[name] then
                error(string.format("no key %q for string found", name))
            end
            return string.format(specifier, (string.gsub(values[name], "%%", "%%%%")))
        end
    )
    local ok
    ok, result = pcall(string.format, result, unpack(values, 2))
    if not ok then
        error(string.format("format error (%q): %s", values[1], result))
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

local function filters(value, ...)
    local result = {}
    if type(value) == "table" then
        for key, value in pairs(value) do
            if value == true then
                result[key] = value
            end
        end
    end
    for index = 1, select("#", ...) do
        result[select(index, ...)] = true
    end
    return result
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

local function catch_error(err)
    if _G.GetRedbeanVersion then
        stderr(tostring(err))
    else
        stderr(debug.traceback(tostring(err)))
    end
end

local send_object

local function parse_compose(chat, compose, only_content, update_type, update_data, ...)

    local users = compose.__super._users

    local user 
    
    if chat then
        user = users:get(tostring(chat._chat_id))
    end

    if not only_content and not user then
        compose:catch("user not found")
        return
    end

    local output = {}
    local texts = {}
    local buttons = {}
    local interactions = {}
    local row = {}
    local data = {}

    local media, media_type, media_spoiler, media_above

    local multipart = false

    local method = "message"

    local transaction = false
    local transaction_label = false
    local payload
    local title, description = {}, {}
    local prices = {}

    compose.say = function(self, ...)
        chat:say(...)
        return self
    end

    compose.send = function(self, ...)
        chat:send(...)
        return self
    end

    compose.id = function()
        return chat:id()
    end

    compose.language = function()
        return chat:language()
    end

    local open_tags = {}
    local function close_tags()
        for index = #open_tags, 1, -1  do
            texts[#texts + 1] = open_tags[index]
        end
        open_tags = {}
    end

    local index = 1
    
    -- runtime
    while index <= #compose do
        local item = compose[index]

        if type(item) == "table" and item._type == "run" and item._indexed ~= compose._id and item._removed ~= true then

            item._indexed = compose._id

            local position = item._position
            if not position then
                compose._position = index + 1
            end
            local result, args = (function(ok, ...)
                if not ok then
                    compose._catch((...))
                    return false
                end
                return ..., list(select(2, ...))
            end)(pcall(item.run, compose, unlist(item.args["#"] > 0 and item.args or select("#", ...) > 0 and list(...) or compose._args)))
            compose._position = position

            if result == false then
                return false
            elseif result then
                if only_content then
                    return false
                end

                send_object(compose, chat._chat_id, chat._language_code, update_type, update_data, result, unlist(args["#"] > 0 and args or (select("#", ...) > 0 and list(...) or list())))

                return false
            end
            
        end
        index = index + 1
    end

    index = 1

    while index <= #compose do

        local item = compose[index]
        if type(item) == "table" and item._type and item._indexed ~= compose._id and item._removed ~= true then

            item._indexed = compose._id

            -- content
            if item._type == "text" then
                texts[#texts + 1] = escape_html(text(chat, item.value))
            elseif item._type == "bold" then
                if open_tags.bold then
                    close_tags()
                end
                texts[#texts + 1] = "<b>"
                if item.value then
                    texts[#texts + 1] = escape_html(text(chat, item.value))
                    texts[#texts + 1] = "</b>"
                    if not open_tags.open then
                        close_tags()
                    end
                else
                    open_tags.bold = true
                    open_tags[#open_tags + 1] = "</b>"
                    open_tags.open = true
                end
            elseif item._type == "italic" then
                if open_tags.italic then
                    close_tags()
                end
                texts[#texts + 1] = "<i>"
                if item.value then
                    texts[#texts + 1] = escape_html(text(chat, item.value))
                    texts[#texts + 1] = "</i>"
                    if not open_tags.open then
                        close_tags()
                    end
                else
                    open_tags.italic = true
                    open_tags[#open_tags + 1] = "</i>"
                    open_tags.open = true
                end
            elseif item._type == "underline" then
                if open_tags.underline then
                    close_tags()
                end
                texts[#texts + 1] = "<u>"
                if item.value then
                    texts[#texts + 1] = escape_html(text(chat, item.value))
                    texts[#texts + 1] = "</u>"
                    if not open_tags.open then
                        close_tags()
                    end
                else
                    open_tags.underline = true
                    open_tags[#open_tags + 1] = "</u>"
                    open_tags.open = true
                end
            elseif item._type == "spoiler" then
                if open_tags.spoiler then
                    close_tags()
                end
                texts[#texts + 1] = "<tg-spoiler>"
                if item.value then
                    texts[#texts + 1] = escape_html(text(chat, item.value))
                    texts[#texts + 1] = "</tg-spoiler>"
                    if not open_tags.open then
                        close_tags()
                    end
                else
                    open_tags.spoiler = true
                    open_tags[#open_tags + 1] = "</tg-spoiler>"
                    open_tags.open = true
                end
            elseif item._type == "strike" then
                if open_tags.strike then
                    close_tags()
                end
                texts[#texts + 1] = "<s>"
                if item.value then
                    texts[#texts + 1] = escape_html(text(chat, item.value))
                    texts[#texts + 1] = "</s>"
                    if not open_tags.open then
                        close_tags()
                    end
                else
                    open_tags.strike = true
                    open_tags[#open_tags + 1] = "</s>"
                    open_tags.open = true
                end
            elseif item._type == "quote" then
                if open_tags.quote then
                    close_tags()
                end
                if item.expandable then
                    texts[#texts + 1] = "<blockquote expandable>"
                else
                    texts[#texts + 1] = "<blockquote>"
                end
                if item.value then
                    texts[#texts + 1] = escape_html(text(chat, item.value))
                    texts[#texts + 1] = "</blockquote>"
                    if not open_tags.open then
                        close_tags()
                    end
                else
                    open_tags.quote = true
                    open_tags[#open_tags + 1] = "</blockquote>"
                    open_tags.open = true
                end
            elseif item._type == "close" then
                if item.value then
                    texts[#texts + 1] = escape_html(text(chat, item.value))
                end
                close_tags()
            elseif item._type == "link" then
                texts[#texts + 1] = '<a href="'
                texts[#texts + 1] = escape_html(item.url)
                texts[#texts + 1] = '">'
                texts[#texts + 1] = escape_html(text(chat, item.label))
                texts[#texts + 1] = "</a>"
            elseif item._type == "mention" then
                texts[#texts + 1] = '<a href="'
                texts[#texts + 1] = escape_html(item.user)
                texts[#texts + 1] = '">'
                texts[#texts + 1] = escape_html(text(chat, item.name))
                texts[#texts + 1] = "</a>"
            elseif item._type == "emoji" then
                texts[#texts + 1] = '<tg-emoji emoji-id="'
                texts[#texts + 1] = escape_html(item.emoji)
                texts[#texts + 1] = '">'
                texts[#texts + 1] = escape_html(text(chat, item.placeholder))
                texts[#texts + 1] = "</tg-emoji>"
            elseif item._type == "mono" then
                texts[#texts + 1] = "<code>"
                texts[#texts + 1] = escape_html(text(chat, item.value))
                texts[#texts + 1] = "</code>"
            elseif item._type == "pre" then
                texts[#texts + 1] = "<pre>"
                texts[#texts + 1] = escape_html(text(chat, item.value))
                texts[#texts + 1] = "</pre>"
            elseif item._type == "code" then
                if item.language then
                    texts[#texts + 1] = '<pre><code class="language-'
                    texts[#texts + 1] = escape_html(item.language)
                    texts[#texts + 1] = '">'
                    texts[#texts + 1] = escape_html(text(chat, item.code))
                else
                    texts[#texts + 1] = "<pre><code>"
                    texts[#texts + 1] = escape_html(text(chat, item.code))
                end
                texts[#texts + 1] = "</code></pre>"
            elseif item._type == "line" then
                if item.value then
                    texts[#texts + 1] = "\n"
                    texts[#texts + 1] = escape_html(text(chat, item.value))
                end
                texts[#texts + 1] = "\n"
            elseif item._type == "html" then
                -- close_tags()
                texts[#texts + 1] = text(chat, item.value)

            -- transaction
            elseif not only_content and item._type == "title" then
                title[#title + 1] = text(chat, item.title)
            elseif not only_content and item._type == "description" then
                description[#description + 1] = text(chat, item.description)
            elseif not only_content and item._type == "price" then
                prices[#prices + 1] = {
                    label = text(chat, item.label),
                    amount = item.amount
                }

            -- misc
            elseif not only_content and item._type == "media" then
                media = item.media
                media_spoiler = item.spoiler
                media_above = item.above
            elseif not only_content and  item._type == "data" then
                data[item.key] = item.value

            -- keyboard
            elseif not only_content and item._type == "button" then
                local event = string.format("Luagram_event_%s", item.event)
                if item.arg ~= nil then
                    event = string.format("%s_%s", event, tostring(item.arg))
                end
                row[#row + 1] = {
                    text = text(chat, item.label),
                    callback_data = event
                }
            elseif not only_content and item._type == "action" then
                if type(item.action) ~= "function" then
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
                    args = item.args["#"] > 0 and item.args or list() -- (select("#", ...) > 0 and list(...) or list())
                }
                user.interactions[uuid] = interaction
                row[#row + 1] = {
                    text = label,
                    callback_data = uuid
                }
            elseif not only_content and item._type == "location" then
                local location = item.location
                if item.params then
                    local params = {}
                    for key, value in pairs(item.params) do
                        if value == true then
                            params[#params + 1] = string.format("%s", escape_path(key))
                        elseif type(value) == "string" or type(value) == "number" then
                            params[#params + 1] = string.format("%s=%s", escape_path(key), escape_path(tostring(value)))
                        end
                    end
                    params = table.concat(params, "&")
                    if string.match(item.location, "[^%?#]$") then
                        location = string.format("%s?%s", location, params)
                    else
                        location = string.format("%s%s", location, params)
                    end
                end
                row[#row + 1] = {
                    text = text(chat, item.label),
                    url = location
                }
            elseif not only_content and item._type == "transaction" then
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
                    transaction_label = true
                end

                local uuid = string.format("Luagram_transaction_%s_%s_%s", chat._chat_id, id(chat), os.time())

                local interaction = {
                    id = item.id,
                    compose = compose,
                    label = label,
                    transaction = item.transaction,
                    interactions = interactions,
                    args = item.args["#"] > 0 and item.args or list() --(select("#", ...) > 0 and list(...) or list())
                }

                payload = uuid

                user.interactions[uuid] = interaction

            elseif not only_content and item._type == "row" then
                if #row > 0 then
                    buttons[#buttons + 1] = row
                    row = {}
                end
            end
        end
        index = index + 1
    end
    close_tags()

    if only_content then
        return table.concat(texts)
    end

    if #row > 0 then
        buttons[#buttons + 1] = row
    end

    if transaction and transaction_label and #buttons > 0 then
        error("Add a label to the transaction function to define actions in this compose")
    end

    if media then
        if string.match(string.lower(media), "^https?://[^%s]+$") then
            media_type = "url"
        elseif string.match(media, "%.") then
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

    if media and media_type == "id" then
        if chat.__super._media_cache[media] then
            method = chat.__super._media_cache[media] 
        else
            local response, err = chat.__super:get_file({
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
            elseif file_path:match("videos") then
                method = "video"
            else
                error(string.format("unknown file type: %s", file_path))
            end
            chat.__super._media_cache[media]  = method
        end

    elseif media and media_type == "url" then

        if chat.__super._media_cache[media] then
            method = chat.__super._media_cache[media] 
        else
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
                elseif content_type == "video/mp4" then
                    method = "video"
                else
                    error(string.format("unknown file content type (%s): %s", media, content_type))
                end
            else
                error(string.format("content type not found for media %s", media))
            end
            chat.__super._media_cache[media]  = method
        end
    elseif media and media_type == "path" then
        if chat.__super._media_cache[media] then
            method = chat.__super._media_cache[media] 
        else
            local extension = string.lower(assert(string.match(media, "([^%.]+)$"), "no extension"))

            if extension == "gif" then
                method = "animation"
            elseif extension == "png" or extension == "jpg" or extension == "jpeg" or extension == "webp" then
                method = "photo"
            elseif extension == "mp4" then
                method = "video"
            else
                error(string.format("unknown media type: %s", media))
            end
            chat.__super._media_cache[media]  = method
        end
    elseif media then
        error(string.format("unknown media type: %s", tostring(media)))
    end

    if transaction then

        if not chat.__super._transaction_provider_token then
            error("You cannot use transaction composes because you have not defined the options transactions.provider_token and transactions.currency")
        end

        if media then
            output.photo_url = media
        end

        method = "invoice"
        output.title = table.concat(title)
        output.description = table.concat(description)
        output.payload = payload
        output.start_parameter = payload
        output.protect_content = true
        output.currency = chat.__super._transaction_currency
        output.provider_token = chat.__super._transaction_provider_token
        output.prices = prices
    else
        
        data.parse_mode = compose._parse_mode

        if method == "animation" then

            if media then
                output.animation = media
                output.has_spoiler = media_spoiler
                output.show_caption_above_media = media_above
                if multipart then
                    compose._multipart = "animation"
                end
            end
            output.caption = table.concat(texts)
        elseif method == "photo" then

            if media then
                output.photo = media
                output.has_spoiler = media_spoiler
                output.show_caption_above_media = media_above
                if multipart then
                    compose._multipart = "photo"
                end
            end
            output.caption = table.concat(texts)
        elseif method == "video" then

            if media then
                output.video = media
                output.has_spoiler = media_spoiler
                output.show_caption_above_media = media_above
                if multipart then
                    compose._multipart = "video"
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
            inline_keyboard = buttons
        }
    end

    for key, value in pairs(data) do
        output[key] = value
    end

    compose._transaction = transaction
    compose._media = media
    compose._method = method
    compose._output = output

    return compose, interactions
end

send_object = function(self, chat_id, language_code, update_type, update_data, name, ...)

    local users = self.__super._users
    local objects = self.__super._objects

    local user = users:get(tostring(chat_id))

    if not user then
        users:set(tostring(chat_id), {
            created_at = os.time(),
            interactions = {}
        })
        user = users:get(tostring(chat_id))
    end
    user.updated_at = os.time()

    local object

    if type(name) == "string" then
        object = objects[name]
        if not object then
            error(string.format("object not found: %s", name))
        end
    elseif type(name) == "table" and name._type then
        object = name
        if not object then
            error(string.format("object not found: %s", name._name))
        end
    else
        error("invalid object")
    end

    local chat = self.__super:chat(chat_id, language_code)

    if object._type == "compose" then

        local this = object:clone()

        this._chat_id = chat_id
        this._language_code = language_code

        this.send = function(self, ...)
            chat:send(...)
            return self
        end

        this.say = function(self, ...)
            chat:say(...)
            return self
        end
        
        this.source = function(self)
            return update_data, update_type
        end

        local result, err = parse_compose(chat, this, false, update_type, update_data, ...)

        if result then

            for index = 1, #object._predispatch do
                object._predispatch[index](result._output, result._multipart)
            end

            local ok, message

            if result._method == "animation" then
                ok, message = self.__super:send_animation(result._output, result._multipart)
            elseif result._method == "photo" then
                ok, message = self.__super:send_photo(result._output, result._multipart)
            elseif result._method == "video" then
                ok, message = self.__super:send_video(result._output, result._multipart)
            elseif result._method == "message" then
                ok, message = self.__super:send_message(result._output, result._multipart)
            elseif result._method == "invoice" then
                ok, message = self.__super:send_invoice(result._output, result._multipart)
            else
                error("invalid method")
            end

            if not ok then
                error(message)
            end

            for index = 1, #object._dispatch do
                object._dispatch[index](result, ok)
            end

        elseif result == nil then
            error(string.format("%s: parser error: %s", this._name, err))
        end

    elseif object._type == "session" then

        if not object._main then
            error(string.format("undefined main session thread: %s", name))
            return
        end

        user.thread = {}

        local thread = user.thread

        chat.listen = function(_, match)
            if type(match) == "function" then
                thread.match = match
            else
                thread.match = nil
            end
            return coroutine.yield()
        end

        chat.cancel = function(self)
            local user = users:get(tostring(self._chat_id))
            if user then
                user.thread = nil
            end
            return self
        end
        
        chat.source = function(self)
            return update_data, update_type
        end

        thread.main = coroutine.create(object._main)
        thread.object = object
        thread.self = chat

        local result, args = (function(ok, ...)

            if not ok then
                object._catch(string.format("error on execute main session thread: %s", ...))
                return
            end
            
            return ..., list(select(2, ...))

        end)(coroutine.resume(thread.main, thread.self, unlist(select("#", ...) > 0 and list(...) or object._args)))

        if coroutine.status(thread.main)  ~= "suspended" then
            user.thread = nil
        end
        
        if result then

            user.thread = nil

            send_object(self, chat._chat_id, chat._language_code, update_type, update_data, result, unlist(args["#"] > 0 and args or (select("#", ...) > 0 and list(...) or list())))

        end

    else

        error(string.format("undefined object type: %s", name))

    end

    return true

end

local addons = {}

addons.compose = function(self)

    self:object("compose", function(self, name, ...)
        self._type = "compose"
        self._id = id(self)
        if name == true then
            self._name = "/start"
            self.__super._objects[self._name] = self
        elseif not name then
            self._name = tostring(self._id)
        else
            self._name = name
            self.__super._objects[self._name] = self
        end
        self._dispatch = {}
        self._predispatch = {}
        self._args = list(...)
        self._parse_mode = "HTML"
        self._position = false
        self:catch(catch_error)
    end, function(self, key)
        local value = rawget(getmetatable(self), key)
        if value == nil and type(key) == "string" then
            local _chat_id = rawget(self, "_chat_id")
            if _chat_id and not string.match(key, "^_") and not string.match(key, "^on_[%w_]+$") then
                return function(self, data, multipart)
                    if type(data) == "table" and data.chat_id == nil then
                        data.chat_id = _chat_id
                    end
                    return assert_level(2, telegram(self, key, data, multipart))
                end
            end
        end
        return value
    end, function(self, value)
        if type(value) == "function" then
            return self:run(value)
        elseif type(value) == "string" then
            return self:text(value)
        elseif type(value) == "number" then
            return self:position(value)
        else
            error(string.format("compose: invalid call %q", tostring(value)))
        end
    end)

    local compose = self.compose

    compose.clone = function(self)
        local clone = self.__super:compose(false)
        for key, value in pairs(self) do
            if key ~= "_id" and key ~= "__super" then
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

    local function insert(self, data)
        if type(self._position) == "number" then
            table.insert(self, self._position, data)
            self._position = self._position + 1
        elseif type(data._position) == "number" then
            table.insert(self, data._position, data)
            data._position = data._position + 1
        else
            table.insert(self, data)
        end
    end
    
    local function item(_type, arg1, arg2, arg3, filter) -- luacheck: ignore
        return function(self, value1, value2, value3)
            local data = {
                _type = _type,
                filter = filters(value1, _type, unlist(filter))
            }
            if arg1 then
               data[arg1] = value1
            end
            if arg2 then
               data[arg2] = value2 
            end
            if arg3 then
               data[arg3] = value3
            end
            insert(self, data)
            return self
        end
    end

    local items = {
        "text", "bold", "italic", "underline", "spoiler", "strike", "mono", "pre", "html", "close"
    }

    for index = 1, #items do
        local _type = items[index]
        compose[_type] = item(_type, "value", nil, nil, list("content"))
    end

    compose.run = function(self, run, ...)
        local args = list(...)
        if type(run) ~= "function" then
            local value = run
            run = function(...)
                return value, ...
            end
        end
        insert(self, {
            _type = "run",
            _position = self._position,
            run = run,
            args = args,
            filter = filters(nil, "run", "runtime")
        })
        return self
    end

    compose.link = function(self, label, url)
        if url == nil then
            url = label
        end
        insert(self, {
            _type = "link",
            url = url,
            label = label,
            filter = filters(label, "link", "content")
        })
        return self
    end

    compose.mention = function(self, name, user)
        if tonumber(user) then
            user = string.format("tg://user?id=%s", user)
        else
            if not name then
                name = user
            end
            user = string.format("https://t.me/%s", user)
        end
        insert(self, {
            _type = "mention",
            user = user,
            name = name,
            filter = filters(name, "mention", "content")
        })
        return self
    end

    compose.emoji = item("emoji", "placeholder", "emoji", nil, list("emoji", "content"))

    compose.code = function(self, language, code)
        if code == nil then
            code = language
            language = nil
        end
        insert(self, {
            _type = "code",
            code = code,
            language = language,
            filter = filters(nil, "code", "content")
        })
        return self
    end

    compose.line = function(self, line)
        insert(self, {
            _type = "line",
            value = line,
            filter = filters(nil, "line", "content")
        })
        return self
    end

    compose.media = item("media", "media", "spoiler", "above", list("misc", "media"))

    compose.quote = item("quote", "value", "expandable", nil, list("content"))

    compose.title = item("title", "title", nil, nil, list("content", "transaction"))

    compose.description = item("description", "description", nil, nil, list("content", "transaction"))

    compose.price = item("price", "label", "amount", nil, list("content", "transaction"))

    compose.data = item("data", "key", "value", nil, list("misc"))

    compose.button = function(self, label, event, arg)
        if #event > 15 or string.match(event, "%W") then
            error(string.format("invalid event name: %s", event))
        end
        if arg and #tostring(arg) > 20 then
            error(string.format("invalid argument: very large value"))
        end
        insert(self, {
            _type = "button",
            label = label,
            event = event,
            arg = arg,
            filter = filters(label, "button", "keyboard")
        })
        return self
    end

    compose.action = function(self, label, action, ...)
        local args = list(...)
        insert(self, {
            _type = "action",
            id = id(self),
            label = label,
            action = action,
            args = args,
            filter = filters(label, "action", "keyboard")
        })
        return self
    end

    compose.location = function(self, label, location, params)
        insert(self, {
            _type = "location",
            label = label,
            location = location,
            params = params,
            filter = filters(label, "location", "keyboard")
        })
        return self
    end

    compose.transaction = function(self, ...)
        local label, transaction = ...
        local args
        if type(label) == "function" then
            transaction = label
            label = false
            args = list(select(2, ...))
        else
            args = list(select(3, ...))
        end
        insert(self, {
            _type = "transaction",
            id = id(self),
            label = label,
            transaction = transaction,
            args = args,
            filter = filters(label, "transaction", "keyboard")
        })
        return self
    end

    compose.row = function(self)
        insert(self, {
            _type = "row",
            filter = filters(nil, "row", "keyboard")
        })
        return self
    end

    compose.content = function(self, ...)
        return parse_compose(nil, self:clone(), true, nil, nil, unlist(select("#", ...) > 0 and list(...) or list()))
    end

    compose.send = function(self, chat_id, language_code, ...)
        local chat = self.__super:chat(chat_id, language_code)
        chat:send(self, ...)
        return self
    end

    compose.dispatch = function(self, dispatch, before)
        if before then
            if dispatch == false then
                self._predispatch = {}
                return self
            end
            self._predispatch[#self._predispatch + 1] = dispatch
        else
            if dispatch == false then
                self._dispatch = {}
                return self
            end
            self._dispatch[#self._dispatch + 1] = dispatch
        end
        return self
    end

    compose.catch = function(self, catch)
        self._catch = function(err)
            catch(string.format("%s: %s", self._name, err))
        end
        return self
    end
    
    compose.position = function(self, ...)
        local position = ...
        local result = self
        if select("#", ...) == 0 then
            if type(self._position) == "number" then
                result = self._position
            else
                result = #self
            end
        else
            if type(position) == "number" and position >= 0 then
                self._position = position
            else
                self._position = false
            end
        end
        return result
    end

    return self
end

addons.session = function(self)

    self:object("session", function(self, name, ...) 
        self._type = "session"
        self._id = id(self)
        if name == true then
            self._name = "/start"
            self.__super._objects[self._name] = self
        elseif not name then
            self._name = tostring(self._id)
        else
            self._name = name
            self.__super._objects[self._name] = self
        end
        self._args = list(...)
        self:catch(catch_error)
    end, nil, function(self, value)
        if type(value) == "function" then
            return self:main(value)
        else
            error(string.format("session: invalid call %q", tostring(value)))
        end
    end)

    local session = self.session

    session.main = function(self, main)
        self._main = main
        return self
    end

    session.send = function(self, chat_id, language_code, ...)
        local chat = self.__super:chat(chat_id, language_code)
        chat:send(self, ...)
        return self
    end

    session.catch = function(self, catch)
        self._catch = function(err)
            catch(string.format("%s: %s", self._name, err))
        end
        return self
    end

    return self
end

addons.chat = function(self)

    self:object("chat", function(self, chat_id, language_code, chat_type)
        self._type = "chat"
        self._chat_id = chat_id
        self._parse_mode = "HTML"
        self._language_code = language_code
        self._chat_type = chat_type
    end, function(self, key)
        local value = rawget(getmetatable(self), key)
        if value == nil and type(key) == "string" then
            if not string.match(key, "^_") and not string.match(key, "^on_[%w_]+$") then
                return function(self, data, multipart)
                    if type(data) == "table" and data.chat_id == nil then
                        data.chat_id = rawget(self, "_chat_id")
                    end
                    return assert_level(2, telegram(self, key, data, multipart))
                end
            end
        end
        return value
    end, function(self, ...)
        return self:say(...)
    end)

    local chat = self.chat

    chat.send = function(self, name, ...)
        send_object(self, self._chat_id, self._language_code, nil, nil, name, ...)
        return self
    end

    chat.say = function(self, ...)
        local texts = {}
        for index = 1, select("#", ...) do
            texts[#texts + 1] = text(self, (select(index, ...)))
        end
        self.__super:send_message({
            chat_id = self._chat_id,
            parse_mode = self._parse_mode,
            text = table.concat(texts, "\n")
        })
        return self
    end

    chat.text = function(self, value)
        return text(self, value)
    end

    chat.id = function(self)
        return self._chat_id
    end

    chat.language = function(self)
        return self._language_code
    end
    
    chat.type = function(self)
        return self._chat_type
    end

    return self
end

----
-- lru.lua
----
local lru = (function()
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
end)()
----

local Luagram = {}

function Luagram.new(options)

    local self = setmetatable({}, Luagram)

    if type(options) == "string" then
        options = {
            token = options,
            debug = true
        }
    end

    assert(type(options) == "table", "invalid param: options")
    assert(type(options.token) == "string", "invalid token")

    self._options = options
    self._ids = 0
    self._objects = {}
    self._events = {}
    self._media_cache = {}
    self._users = lru.new(options.cache or 1024)
    self._catch = catch_error
    self.__super = self

    self._token = options.token
    self._api = options.api
    self._headers = options.headers
    
    if type(options.transactions) == "table" then
        self._transaction_report_to = assert(options.transactions.report_to, "required option: transactions.report_to")
        self._transaction_currency = assert(options.transactions.currency, "required option: transactions.currency")
        self._transaction_provider_token = assert(options.transactions.provider_token, "required option: transactions.provider_token")
    elseif type(options.transactions) == "string" or type(options.transactions) == "number" then
        self._transaction_report_to = options.transactions
        self._transaction_currency = "XTR"
        self._transaction_provider_token = ""
    end

    self._http_provider = options.http_provider
    self._json_encoder = options.json_encoder
    self._json_decoder = options.json_decoder
    self._sleep_fn = options._sleep_fn

    self._debug = options.debug

    if not options.http_provider then
        if _G.GetRedbeanVersion then
            self._http_provider = function(url, params)
                local status, headers, body = _G.Fetch(url, params)
                return body, status, headers
            end
        elseif _G.ngx then
            local http = require("lapis.nginx.http")
            local ltn12 = require("ltn12")
            self._http_provider = function(url, params)
                local out = {}
                if not params then
                    params = {}
                end
                if params.body then
                    params.source = ltn12.source.string(params.body)
                end
                params.sink = ltn12.sink.table(out)
                params.url = url
                local _, status, headers = http.request(params)
                local response = table.concat(out)
                return response, status, headers
            end
        else
            local https = require("ssl.https")
            local ltn12 = require("ltn12")
            self._http_provider = function(url, params)
                local out = {}
                if not params then
                    params = {}
                end
                if params.body then
                    params.source = ltn12.source.string(params.body)
                end
                params.sink = ltn12.sink.table(out)
                params.url = url
                local _, status, headers = https.request(params)
                local response = table.concat(out)
                return response, status, headers
            end
        end
    else
        local ltn12 = require("ltn12")
        if type(options.http_provider) == "table" and type(options.http_provider.request) == "function" then
            options.http_provider = options.http_provider.request
        end
        self._http_provider = function(url, params)
            local out = {}
            if not params then
                params = {}
            end
            if params.body then
                params.source = ltn12.source.string(params.body)
            end
            params.sink = ltn12.sink.table(out)
            params.url = url
            local _, status, headers = options.http_provider(params)
            local response = table.concat(out)
            return response, status, headers
        end
    end

    if not self._json_encoder then
        if _G.GetRedbeanVersion then
            self._json_encoder = _G.EncodeJson
        elseif _G.ngx then
            local json = require("cjson")
            self._json_encoder = json.encode
        else
            local ok, cjson = pcall(require, "cjson")
            if ok then
                self._json_encoder = cjson.encode
            else
                local json = require("json")
                self._json_encoder = json.encode
            end
        end
    end

    if not self._json_decoder then
        if _G.GetRedbeanVersion then
            self._json_decoder = _G.DecodeJson
        elseif _G.ngx then
            local json = require("cjson")
            self._json_decoder = json.decode
        else
            local ok, cjson = pcall(require, "cjson")
            if ok then
                self._json_decoder = cjson.decode
            else
                local json = require("json")
                self._json_decoder = json.decode
            end
        end
    end

    if not self._sleep_fn then
        if _G.GetRedbeanVersion then
            self._sleep_fn = _G.Sleep
        elseif _G.ngx then
            self._sleep_fn = _G.ngx.sleep
        else
            local socket = require("socket")
            self._sleep_fn = function(secs)
                socket.select(nil, nil, secs)
            end
        end
    end

    if options.webhook then
        self._webhook = {}
        if type(options.webhook) == "table" then
            self._webhook = options.webhook
        elseif type(options.webhook) == "string" then
            self._webhook.url = options.webhook
        else
            error("invalid webhook")
        end
        assert(type(self._webhook.url) == "string", "required option: webhook.url")
    end
    if not options.webhook then
        self._get_updates = {}
        if type(options.get_updates) == "table" then
            self._get_updates = options.get_updates
        elseif type(options.get_updates) == "number" then
            self._get_updates.timeout = options.get_updates
        end
        if not self._get_updates.timeout then
            self._get_updates.timeout = 30
        end
    end

    self:addon("compose")
    self:addon("session")
    self:addon("chat")

    self:on_unhandled(stdout)

    return self
end

function Luagram:object(name, new, index, call)
    local class = {}
    class.__index = index or class
    class.__call = call
    self[name] = setmetatable({}, {
        __call = function(_, base, ...)
            local self = setmetatable({}, class)
            self.__name = name
            self.__super = base
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
        local event = string.match(key, "^on_([%w_]+)$")
        if event then
            return function(self, callback)
                self._events[event] = callback
                return self
            end
        elseif not string.match(key, "^_") then
            return function(self, data, multipart)
                return assert_level(2, telegram(self, key, data, multipart))
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
    package.path = "addons/?.lua;" .. path
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
        package.path = "locales/?.lua;" .. path
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

    local user = self._users:get(tostring(chat_id))

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
        pcall(self.__super.answer_callback_query, self.__super, answer)
        return true
    end

    action.lock = true

    local this = action.compose:clone()

    this._update_data = update_data
    this._update_type = "callback_query"
    this._language_code = language_code
    this._chat_id = chat_id

    local chat = self:chat(chat_id, language_code)

    this.say = function(self, ...)
        chat:say(...)
        return self
    end

    this.send = function(self, ...)
        chat:send(...)
        return self
    end

    this.id = function()
        return chat:id()
    end

    this.language = function()
        return chat:language()
    end

    this.source = function(self)
        return self._update_data, self._update_type
    end

    this.this = function(self, new_label, new_action, ...)
        for index = 1, #self do
            if type(self[index]) == "table" and self[index]._type == "action" and self[index].id == action.id then
                self[index].position = index + 1
                if new_label ~= nil then
                    self[index].label = new_label
                end
                if new_action ~= nil then
                    self[index].action = new_action
                end
                if select("#", ...) > 0 then
                    self[index].args = list(...)
                end
                return self[index]
            end
        end
        return nil
    end

    this.filter = function(self, ...)
        local results = {}
        local items = {}
        for index = 1, #self do
            local item = self[index]
            if type(item) == "table" and type(item.filter) == "table" then
                for index2 = 1, select("#", ...) do
                    local filter = select(index2, ...)
                    if type(filter) == "table" then
                        for key in pairs(filter) do
                            if item.filter[key] == true and not items[item] then
                                items[item] = true
                                results[#results + 1] = item
                            end
                        end
                    elseif type(filter) == "string" then
                        if type(item.label) == "string" and string.match(item.label, filter) and not items[item] then
                            items[item] = true
                            results[#results + 1] = item
                        elseif type(item.value) == "string" and string.match(item.value, filter) and not items[item] then
                            items[item] = true
                            results[#results + 1] = item
                        elseif type(item.label) == "table" and type(item.label[1]) == "string" and string.match(item.label[1], filter) and not items[item] then
                            items[item] = true
                            results[#results + 1] = item
                        elseif type(item.value) == "table" and type(item.value[1]) == "string" and string.match(item.value[1], filter) and not items[item] then
                            items[item] = true
                            results[#results + 1] = item
                        end
                    end
                end
            end
        end
        return results
    end

    this.remove = function(self, ...)
        local results = self:filter(...)
        for index = 1, #results do
            results[index]._removed = true
        end
        return self
    end
    
    this.reinsert = function(self, ...)
        local results = self:filter(...)
        for index = 1, #results do
            results[index]._removed = nil
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
    
    this:remove({runtime = true})

    local _ = (function(success, response, ...)

        if not success then
            action.compose._catch(response)
            return
        end

        local args

        if response == true then
            this = self.compose.clone(action.compose._origin)
            args = action.compose._origin._args
        elseif response == false then
            this:remove({keyboard = true})
        elseif type(response) == "string" then
            local object = self.__super._objects[response]
            if object then
                if object._type == "compose" then
                    this = self.compose.clone(object)
                elseif object._type == "session" then
                    for _, value in pairs(action.interactions) do
                        user.interactions[value] = nil
                    end
                    pcall(self.__super.delete_message, self.__super, {
                        chat_id = chat_id,
                        message_id = update_data.message.message_id
                    })
                    send_object(self, chat_id, language_code, "callback_query", update_data, object._name, unlist(select("#", ...) > 0 and list(...) or action.args))
                    return
                else
                   error(string.format("invalid object: %s", object._type))
                end
            else
                error(string.format("object not found: %s", response))
            end
        elseif type(response) == "table" and response._type == "session" then
            for _, value in pairs(action.interactions) do
                user.interactions[value] = nil
            end
            pcall(self.__super.delete_message, self.__super, {
                chat_id = chat_id,
                message_id = update_data.message.message_id
            })
            send_object(self, chat_id, language_code, "callback_query", update_data, response, unlist(select("#", ...) > 0 and list(...) or action.args))
            return
        elseif type(response) == "table" and response._type == "compose" then
            this = response
        elseif response == nil then
            return
        else
            error("invalid result")
        end

        if action.compose._media then
            local media
            for index = #this, 1, -1 do
                if type(this[index]) == "table" and this[index]._type == "media" then
                    media = this[index].media
                    break
                end
            end
            if not media then
                this:media(action.compose._media)
            end
        end

        local result, err = parse_compose(chat, this:clone(), false, "callback_query", update_data, unlist(select("#", ...) > 0 and list(...) or args or list()))
        if result == nil then
            action.compose._catch(string.format("parser error: %s", err))
        end
        if not result then
            return
        end
        
        for _, value in pairs(action.interactions) do
            user.interactions[value] = nil
        end

        local ok, message

        if action.compose._transaction then

            pcall(self.__super.delete_message, self.__super, {
                chat_id = chat_id,
                message_id = update_data.message.message_id
            })
            if result._method == "animation" then
                ok, message = self.__super:send_animation(result._output, result._multipart)
            elseif result._method == "photo" then
                ok, message = self.__super:send_photo(result._output, result._multipart)
            elseif result._method == "video" then
                ok, message = self.__super:send_video(result._output, result._multipart)
            elseif result._method == "message" then
                ok, message = self.__super:send_message(result._output, result._multipart)
            elseif result._method == "invoice" then
                ok, message = self.__super:send_invoice(result._output, result._multipart)
            else
                error("invalid method")
            end

            if not ok then
                action.compose._catch(message)
            end

            return
        end

        if action.compose._method == "message" and result._method == "message" then
            result._output.chat_id = chat_id
            result._output.message_id = update_data.message.message_id
            ok, message = self.__super:edit_message_text(result._output)
        elseif action.compose._method ~= "message" and result._method == "message" then
            result._output.chat_id = chat_id
            result._output.message_id = update_data.message.message_id
            ok, message = self.__super:edit_message_caption(result._output)
        elseif (action.compose._method == "message" and result._method ~= "message") or (action.compose._method ~= result._method) then
            pcall(self.__super.delete_message, self.__super, {
                chat_id = chat_id,
                message_id = update_data.message.message_id
            })
            if result._method == "animation" then
                ok, message = self.__super:send_animation(result._output, result._multipart)
            elseif result._method == "photo" then
                ok, message = self.__super:send_photo(result._output, result._multipart)
            elseif result._method == "video" then
                ok, message = self.__super:send_video(result._output, result._multipart)
            elseif result._method == "message" then
                ok, message = self.__super:send_message(result._output, result._multipart)
            elseif result._method == "invoice" then
                ok, message = self.__super:send_invoice(result._output, result._multipart)
            else
                error("invalid method")
            end
        elseif action.compose._method == result._method then
            result._output.media = result._output
            result._output.media.type = result._method
            if result._multipart then
                result._output.media.media = string.format("attach://%s", result._multipart)
            else
                result._output.media.media = result._media
            end
            result._output.chat_id = chat_id
            result._output.message_id = update_data.message.message_id
            ok, message = self.__super:edit_message_caption(result._output)
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
    pcall(self.__super.answer_callback_query, self.__super, answer)

    return true
end

local function shipping_query(self, chat_id, language_code, update_data)

    local payload = update_data.invoice_payload

    if not payload:match("^Luagram_transaction_%d+_%d+_%d+$") then
        return false
    end

    local user = self._users:get(tostring(chat_id))

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
            pcall(self.__super.answer_shipping_query, self.__super, {
                shipping_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
            })
            catch(string.format("error on proccess shipping query: %s", ...))
            return
        end

        local result = ...

        if type(result) == "string" then
            pcall(self.__super.answer_shipping_query, self.__super, {
                shipping_query_id = update_data.id,
                ok = false,
                error_message = text(self, result)
            })
            return
        elseif result == false then
            pcall(self.__super.answer_shipping_query, self.__super, {
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
                    pcall(self.__super.answer_shipping_query, self.__super, {
                        shipping_query_id = update_data.id,
                        ok = false,
                        error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
                    })
                    catch(string.format("error on proccess shipping query: invalid return value"))
                    return
                end
            end
            pcall(self.__super.answer_shipping_query, self.__super, {
                shipping_query_id = update_data.id,
                ok = true,
                shipping_options = options
            })
            return
        end
        
        pcall(self.__super.answer_shipping_query, self.__super, {
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

    local user = self._users:get(tostring(chat_id))

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
        return "review"
    end

    this.source = function()
        return update_data, "pre_checkout_query"
    end

    local _ = (function(ok, ...)

        if not ok then
            pcall(self.__super.answer_pre_checkout_query, self.__super, {
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Unfortunately, there was an issue while proceeding with this payment."})
            })
            catch(string.format("error on proccess pre checkout query: %s", ...))
            return
        end

        local result = ...

        if type(result) == "string" then
            pcall(self.__super.answer_pre_checkout_query, self.__super, {
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = text(self, result)
            })
            return
        elseif result == false then
            pcall(self.__super.answer_pre_checkout_query, self.__super, {
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = text(self, {"Sorry, it won't be possible to complete the payment for the item you selected. Please try again in the bot."})
            })
            return
        elseif result == true then
            pcall(self.__super.answer_pre_checkout_query, self.__super, {
                pre_checkout_query_id = update_data.id,
                ok = true
            })
            return
        end
        
        pcall(self.__super.answer_pre_checkout_query, self.__super, {
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
        return false, "Transaction identifier not found in this session. Please manually contact the payer to resolve the outcome of this payment."
    end

    local user = self._users:get(tostring(chat_id))

    if not user then
        return false, "Transaction user not found in this session. Please manually contact the payer to resolve the outcome of this payment."
    end

    local transaction = user.interactions[payload]

    if not transaction then
        return false, "Transaction compose not found in this session. Please manually contact the payer to resolve the outcome of this payment."
    end

    local this = self:chat(chat_id, language_code)

    this.status = function()
        return "complete"
    end

    this.source = function()
        return update_data, "successful_payment"
    end

    return true, pcall(transaction.transaction, this, unlist(transaction.args))
end

local function chat_id(update_data, update_type)
    local language = "en"
    if update_data.from and update_data.from.language_code then
        language = update_data.from.language_code
    end
    if update_type == "callback_query" then
        return update_data.message.chat.id, language, update_data.message.chat.type
    elseif update_type == "pre_checkout_query" or update_type == "shipping_query" then
        return update_data.from.id, language, update_data.chat.type
    end
    return assert(update_data.chat.id, "chat_id not found"), language, update_data.chat.type
end

local function parse_update(self, update)
    local update_type, update_data

    assert(type(update) == "table", "invalid update")
    assert(update.update_id, "invalid update")

    for key, value in pairs(update) do
        if key ~= "update_id" and key ~= "_response" then
            update_type = key
            update_data = value
            break
        end
    end

    if not update_type or not update_data then
        error("invalid update")
    end

    local chat_id, language_code = chat_id(update_data, update_type)
    
    local user = self._users:get(tostring(chat_id))

    if update_type == "callback_query" then

        if callback_query(self, chat_id, language_code, update_data) == true then
            return self
        end

        local event, has_arg, arg = string.match(update_data.data, "^Luagram_event_(%w+)(_?)(.*)$")

        if event then

            if has_arg ~= "_" then
                arg = nil
            end

            if self._events[event] and self._events[event](update_data, arg) ~= false then
                pcall(self.__super.answer_callback_query, self.__super, {
                    callback_query_id = update_data.id
                })
                return self
            end

            if self._events[true] then
                self._events[true](update_data, arg)
                pcall(self.__super.answer_callback_query, self.__super, {
                    callback_query_id = update_data.id
                })
                return self
            end

            if self._events.unhandled then
                self._events.unhandled(update._response)
                return self
            end

            error(string.format("unhandled update: %s", update._response))
            return self

        end

        local time = string.match(update_data.data, "^Luagram_action_%d+_%d+_(%d+)$")
        if time and (not user or tonumber(time) < user.created_at) then
            if update_data.from and update_data.from.is_bot ~= true and update_data.message and update_data.message.chat.type == "private" then
                pcall(self.__super.answer_callback_query, self.__super, {
                    callback_query_id = update_data.id,
                    text = text(self:chat(chat_id, language_code), {"Welcome back! This message is outdated. Let's start over!"})
                })
                if send_object(self, chat_id, language_code, update_type, update_data, "/start") == true then
                    return self
                end
            else
                pcall(self.__super.answer_callback_query, self.__super, {
                    callback_query_id = update_data.id,
                    text = text(self:chat(chat_id, language_code), {"Welcome back! This message is outdated."})
                })
                return self
            end
        end

    elseif update_type == "shipping_query" then

        if shipping_query(self, chat_id, language_code, update_data) == true then
            return self
        end

        if string.match(update_data.invoice_payload, "^Luagram_transaction_%d+_%d+_%d+$") then
            pcall(self.__super.answer_shipping_query, self.__super, {
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
            pcall(self.__super.answer_pre_checkout_query, self.__super, {
                pre_checkout_query_id = update_data.id,
                ok = false,
                error_message = text(self:chat(chat_id, language_code), {"Unfortunately, it wasn't possible to complete this payment. Please start the process again in the bot."})
            })
            return self
        end

    elseif update_type == "message" and update_data.successful_payment  then

        if (function(ok, ...)

            if string.match(update_data.successful_payment.invoice_payload, "^Luagram_transaction_%d+_%d+_%d+$") then

                local admin = self.__super:chat(self.__super._transaction_report_to)
                local html = {"<b>Payment Report</b>", "", "<blockquote expandable><b>Telegram Response:</b>"}
                local function serialize(items, level)
                    if level > 10 then
                        return
                    end
                    for key, value in pairs(items) do
                        if type(value) == "table" then
                            html[#html + 1] = string.format("<i>%s</i>:", escape_html(key))
                            serialize(value, level + 1)
                        else
                            html[#html + 1] = string.format("%s<i>%s</i>: %s", string.rep("  ", level), escape_html(key), escape_html(value))
                        end
                    end
                end
                serialize(update_data, 0)
                html[#html + 1] = "</blockquote>"
                html[#html + 1] = "<blockquote expandable><b>Luagram Response:</b>"
                local response = {...}
                if response[1] == true then
                    response[1] = "Compose complete payment event executed without errors"
                    if #response <= 1 then
                        response[2] = "Compose complete payment event did not return any value. It is recommended that this event returns some value to report that everything is OK."
                    end
                elseif response[1] == false then
                    response[1] = "An error occurred in the compose complete payment event. Manually check with the payer if everything is OK."
                end
                serialize(response, 0)
                html[#html + 1] = "</blockquote>"
                admin:send_message({
                    text = table.concat(html, "\n"),
                    parse_mode = "HTML"
                })

                ok = true
            end

            if ok then
                return true
            end

        end)(successful_payment(self, chat_id, language_code, update_data)) == true then
            return self
        end

    end

    if not user then
        self._users:set(tostring(chat_id), {
            created_at = os.time(),
            interactions = {}
        })
        user = self._users:get(tostring(chat_id))
    end
    user.updated_at = os.time()

    if update_type == "message" and update_data.text then
        local text = update_data.text
        local command, space, payload = string.match(text, "^(/[a-zA-Z0-9_]+)(.?)(.*)$")
        if command and self.__super._objects[command] then
            user.thread = nil
            if space == " " and payload ~= "" then
                if send_object(self, chat_id, language_code, update_type, update_data, command, payload) == true then
                    return self
                end
            else
                if send_object(self, chat_id, language_code, update_type, update_data, command) == true then
                    return self
                end
            end
        end
    end

    local thread = user.thread

    if thread then

        if coroutine.status(thread.main) ~= "suspended" then
            user.thread = nil
        else

            local response_args
            local valid = true
            if thread.match then
                valid = false
                local response, value, args = (function(ok, ...)
                    if not ok then
                        thread.object._catch(string.format("error on match session thread: %s", ...))
                        return nil
                    end
                    return select("#", ...) > 0, ..., list(select(2, ...))
                end)(pcall(thread.match, update))
            
                if response and value == true then
                    valid = true
                    response_args = args
                elseif response and value == false then
                    if args["#"] > 0 then
                        thread.self:say(unlist(args))
                    end
                elseif response and (type(value) == "string" or type(value) == "table") then
                    user.thread = nil
                    send_object(self, chat_id, language_code, update_type, update_data, value, unlist(args["#"] > 0 and args or list()))
                elseif response and value == nil then
                    if args["#"] > 0 then
                        thread.self:say(unlist(args))
                    end
                    user.thread = nil
                end
            end

            if valid then

                local result, args = (function(ok, ...)

                    if not ok then
                        thread.object._catch(string.format("error on execute main session thread: %s", ...))
                        return
                    end

                    return ..., list(select(2, ...))

                end)(coroutine.resume(thread.main, update, unlist(response_args or list())))

                if coroutine.status(thread.main) ~= "suspended" then
                    user.thread = nil
                end

                if result then
                    
                    user.thread = nil

                    send_object(self, chat_id, language_code, update_type, update_data, result, unlist(args["#"] > 0 and args or list()))

                end

            end

            return self
        end
    end

    if self._events[update_type] then
        if self._events[update_type](update_data) ~= false then
            return self
        end
    end

    if self._events[true] then
        self._events[true](update)
        return self
    end

    if update_type == "message" and update_data.from and update_data.from.is_bot ~= true and update_data.chat and update_data.chat.type == "private" then
        if send_object(self, chat_id, language_code, update_type, update_data, "/start") == true then
            return self
        end
    end

    if self._events.unhandled then
        self._events.unhandled(update._response)
        return self
    end

    error(string.format("unhandled update: %s", update._response))
end

function Luagram:request(...)
    return request(self, ...)
end

function Luagram:json(value)
    if type(value) == "string" then
        return self.__super._json_decoder(value)
    end
    return self.__super._json_encoder(value)
end

function Luagram:update(...)
    if _G.GetRedbeanVersion and select("#", ...) == 0 then
        if self._stop ~= false then
            return false
        end
        if not self._webhook then
            return false
        end
        if not self._redbean_mapshared then
            return false
        end
        local path = string.match(self._webhook.url, "^[hH][tT][tT][pP][sS]?://.-/(.*)$")
        if not path or _G.GetPath() ~= string.format("/%s", path) then
            return false
        end
        if self._webhook.secret_token and _G.GetHeader("X-Telegram-Bot-Api-Secret-Token") ~= self._webhook.secret_token then
            return false
        end
        if _G.GetMethod() ~= "POST" then
            return false
        end
        local body = _G.GetBody()
        local response = _G.DecodeJson(body)
        if type(response) ~= "table" then
            return false
        end
        self._redbean_mapshared:write(body)
        self._redbean_mapshared:wake(0)
        _G.SetStatus(200)
        _G.Write("ok")
        return true
    end
    if self._stop ~= false then
        return self
    end
    local update = ...
    xpcall(function()
        if type(update) ~= "table" then
            error(string.format("invalid update: %s", update))
        end
        parse_update(self, update)
    end, self._catch)
    return self
end

function Luagram:start()
    if _G.GetRedbeanVersion then
        if self._webhook then
            if self._webhook.set_webhook ~= false then
                self._webhook.set_webhook = nil
                self.__super:set_webhook(self._webhook)
            end
            self._redbean_mapshared = assert(_G.unix.mapshared(1024 * 1024))
            self._stop = false
            if assert(_G.unix.fork()) == 0 then
                _G.unix.sigaction(_G.unix.SIGTERM, _G.unix.exit)
                local function wait()
                    self._redbean_mapshared:wait(0, 0)
                    local update = self._redbean_mapshared:read()
                    self._redbean_mapshared:write("\0\0\0\0\0\0\0\0")
                    local response = _G.DecodeJson(update)
                    if response then
                        self:update(response)
                    end
                    collectgarbage()
                    return wait() -- tail call
                end
                self._redbean_mapshared:write("\0\0\0\0\0\0\0\0")
                wait()
            end
        elseif self._get_updates then
            self.__super:delete_webhook()
            if assert(_G.unix.fork()) == 0 then
                _G.unix.sigaction(_G.unix.SIGTERM, _G.unix.exit)
                self._stop = false
                local offset
                local function polling()
                    if self._stop then
                        self._stop = nil
                        _G.unix.exit()
                        return
                    end
                    self._get_updates.offset = offset
                    local ok, result = pcall(self.__super.get_updates, self.__super, self._get_updates)
                    if ok and result then
                        for index = 1, #result do
                            local update = result[index]
                            update._response = result._response
                            offset = update.update_id + 1
                            self:update(update)
                        end
                    else
                        self._catch(tostring(result))
                    end
                    collectgarbage()
                    -- _G.unix.nanosleep(1)
                    return polling() -- tail call
                end
                polling()
            end
        end
        return self
    else
        if self._webhook then
            if self._webhook.set_webhook ~= false then
                self._webhook.set_webhook = nil
                self.__super:set_webhook(self._webhook)
            end
            self._stop = false
        elseif self._get_updates then
            self.__super:delete_webhook()
            local offset
            self._stop = false
            local function polling()
                if self._stop then
                    self._stop = nil
                    return
                end
                self._get_updates.offset = offset
                local ok, result = pcall(self.__super.get_updates, self.__super, self._get_updates)
                if ok and result then
                    for index = 1, #result do
                        local update = result[index]
                        update._response = result._response
                        offset = update.update_id + 1
                        self:update(update)
                    end
                else
                    self._catch(result)
                end
                collectgarbage()
                return polling() -- tail call
            end
            polling()
            return self
        end
    end
end

function Luagram:stop()
    self._stop = true
    return self
end

return setmetatable(Luagram, {
    __call = function(self, ...)
        return self.new(...)
    end
})
