local Luagram = require("Luagram")

local function new()
    return Luagram.new({
        token = "",
        http_provider = true,
        json_encoder = function(...) return ... end,
        json_decoder = function(...) return ... end
    })
end

local function test(bot, update, fn)
    bot._http_provider = function(_, options)
        fn(options.body)
        return {ok = true, result = options.body}, 200
    end
    bot:update(update)
end


describe("compose", function()

        it("receive '/start', send 'ok'", function()

            local bot  = new()

            bot:compose("/start"):text("ok")

            test(bot, {
                update_id = 842537796,
                message = {
                    message_id = 1282,
                    entities = {
                        {
                            type = "bot_command",
                            length = 6,
                            offset = 0,
                        },
                    },
                    date = 1703212313,
                    from = {
                        is_bot = false,
                        first_name = "Lua",
                        id = 101010101,
                        last_name = "gram",
                        language_code = "en",
                        username = "Luagram",
                    },
                    chat = {
                        first_name = "Lua",
                        id = 101010101,
                        type = "private",
                        username = "Luagram",
                        last_name = "gram",
                    },
                    text = "/start",
                },
            },
            function(r) assert.are.same(r, {
                chat_id = 101010101,
                parse_mode = "HTML",
                text = "ok",
            }) end)

        end)

end)