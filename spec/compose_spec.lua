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

        it("receive '/start text from command', send formatted message", function()

            local bot  = new()

            bot:compose("/start")
            :text("start"):line()
            :text("escape test <>\"&"):line()
            :line("line no blank line")
            :bold("bold"):line()
            :italic("italic"):line()
            :underline("underline"):line()
            :spoiler("spoiler"):line()
            :strike("strike"):line()
            :bold():underline():line("bold + underline + line")
            :link("with-label", "https://with-label.com"):line()
            :link("https://no-label.com"):line()
            :mention("user_with_username_and_name", "User with username and name"):line()
            :mention("user_only_username"):line()
            :emoji("10101010", "👋"):line()
            :mono("mono"):line()
            :pre("pre\n\tpre\npre"):line()
            :code("lua", "print('code in Lua')"):line()
            :code("if not nil then print('code auto detect') end"):line()
            :html("<b>raw html &amp;</b>"):line()
            :bold():italic("bold + italic"):line()
            :bold():italic():underline():strike("bold + italic + underline + strike"):line()
            :underline():spoiler("underline + spoiler"):line()
            :text(1, "begin"):line(2)
            :run(function(self, payload)
                self:text(payload):line("runtime line")
            end)
            :text("final")

            test(bot, {
                update_id = 842537824,
                message = {
                    message_id = 1334,
                    entities = {
                        {
                            type = "bot_command",
                            length = 6,
                            offset = 0,
                        },
                    },
                    date = 1703292291,
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
                    text = "/start text from command",
                },
            },
            function(r) assert.are.same(r, {
                chat_id = 101010101,
                parse_mode = "HTML",
                text = "begin\nstart\nescape test &lt;&gt;&quot;&amp;\n\nline no blank line\n<b>bold</b>\n<i>italic</i>\n<u>underline</u>\n<tg-spoiler>spoiler</tg-spoiler>\n<s>strike</s>\n<b><u>\nbold + underline + line</u></b>\n<a href=\"https://with-label.com\">with-label</a>\n<a href=\"https://no-label.com\">https://no-label.com</a>\n<a href=\"https://t.me/user_with_username_and_name\">User with username and name</a>\n<a href=\"https://t.me/user_only_username\">user_only_username</a>\n<tg-emoji emoji-id=\"10101010\">👋</tg-emoji>\n<code>mono</code>\n<pre>pre\n	pre\npre</pre>\n<pre><code class=\"language-lua\">print('code in Lua')</code></pre>\n<pre><code>if not nil then print('code auto detect') end</code></pre>\n<b>raw html &amp;</b>\n<b><i>bold + italic</i></b>\n<b><i><u><s>bold + italic + underline + strike</s></u></i></b>\n<u><tg-spoiler>underline + spoiler</tg-spoiler></u>\ntext from command\nruntime line\nfinal",
            }) end)

        end)

end)