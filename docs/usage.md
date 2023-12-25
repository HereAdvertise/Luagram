---
title: Basic usage
layout: default
nav_order: 3
---

Below is an example of **Hello world**. This code is similar to what you find in other Telegram bot libraries. Luagram can do much more than that!

{: .lang .lua }
```lua
local Luagram = require("Luagram")

local bot = Luagram.new("...your token from Botfather...")

bot:on_message(function(message)
    bot:send_message({
        chat_id = message.chat.id,
        text = "Hello World!"
    })
end)
```

{: .lang .lua_chain .hidden }
```lua
local Luagram = require("Luagram")

local bot = Luagram.new("...your token from Botfather...")

bot:on_message(function(message)
    bot:send_message({
        chat_id = message.chat.id,
        text = "Hello World!"
    })
end)
```

{: .lang .moon .hidden }
```moonscript
Luagram = require "Luagram"

bot = Luagram.new "...your token from Botfather..."

bot\on_message (messsage) ->
    bot\send_message
        chat_id: message.chat.id,
        text: "Hello World!"
```

{: .lang .moon_chain .hidden }
```moonscript
Luagram = require "Luagram"

with Luagram.new "...your token from Botfather..."

    \on_message (messsage) ->
        \send_message
           chat_id: message.chat.id,
           text: "Hello World!"
```

<div class="tg">
    <div class="tg-right">
        <div>
            <span>/start</span>
        </div>
    </div>
    <div class="tg-left">
        <div>
            Hello World!
        </div>
    </div>
</div>