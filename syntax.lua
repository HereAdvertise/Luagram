local luagram = require("luagram")

local bot = luagram.new("token")

bot:compose("/command", {
    on_send = function(message)

    end,
    data = {
        -- ...
    },
    media = false,
    format = "HTML",
    "text",
    "description",
    format = "html",
    function(self, ...)
        self:send("aaa")
        self:send({
            name = "",
            chat_id = ...
        })
        self:say("...")

        return ...
    end,
    bot:btn("label", function(this, ...)

        this:say("ok")
        this:send("go")

        local compose = self.compose()
        compose[#compose + 1] = "ok" -- __len

        self:send("")

        return compose, "notification" -- {...}
    end),
    bot:pay("optional label", function(success) end, function(checkout) end, function(shipping) end),
    {bot:btn(), bot:btn()},
    btn:url("label", "https://google.com")
}, ...)