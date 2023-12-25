---
title: Home
layout: home
nav_order: 1
---

**[Luagram](https://github.com/Propagram/Luagram)** is a [Lua](https://lua.org) library for creating chatbots for [Telegram](https://core.telegram.org/bots/api).

It has been designed from the ground up to be intuitive and fast. When using Luagram, challenging tasks become easy, as it not only provides basic features but also offers capabilities not found in other libraries.

### Luagram Features

 * **Composes:** A powerful API for sending stylized messages, media, and even transactions to users.
 * **Sessions:** Continue and pause conversations with users intuitively.
 * **Commands:** Define functions for predefined commands.
 * **Events:** Create events that respond to updates and compose buttons.
 * **Translations:** Send messages to your users in their language.
 * **Addons:** It's straightforward to add or create addons for Luagram.

### Basic Usage

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

At the bottom of this documentation, you can change the programming language between **Lua** or **Moonscript** ([a Lua dialect](others/lua-dialects.html)) and also the programming style. The *chain* style closely resembles *jQuery*. Choose the option that suits you best. Your selection will be remembered on this device every time you access this documentation. All examples in this documentation are displayed in the language/style you have chosen. You can change it at any time.

### License

Luagram is distributed by an [MIT license](https://github.com/Propagram/Luagram/blob/main/LICENSE).

### Contributing

If you wish to contribute to the project, you can suggest pull requests in our [GitHub repository](https://github.com/Propagram/Luagram). Code and documentation improvements and fixes are always welcome!