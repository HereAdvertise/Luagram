local Luagram = require("Luagram")

local function new()
    return Luagram({
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


describe("button", function()

        it("on_ok", function()

            local bot  = new()

            bot:compose("/t"):text("content"):button("button", "ok")

            bot:on_ok(function(update)
                assert.are.same(update, {
                    data = "Luagram_event_ok",
                    chat_instance = "-6184452786735168277",
                    from = {
                        is_bot = false,
                        first_name = "Lua",
                        id = 101010101,
                        last_name = "gram",
                        language_code = "en",
                        username = "Luagram",
                    },
                    message = {
                        reply_markup = {
                            inline_keyboard = {
                                {
                                    {
                                        text = "button",
                                        callback_data = "Luagram_event_ok",
                                    },
                                },
                            },
                        },
                        message_id = 1348,
                        date = 1703358175,
                        from = {
                            is_bot = true,
                            username = "luagrambot",
                            first_name = "LUAGRAM",
                            id = 202020202,
                        },
                        chat = {
                            first_name = "Lua",
                            id = 101010101,
                            type = "private",
                            username = "Luagram",
                            last_name = "gram",
                        },
                        text = "content",
                    },
                    id = "622150475951426722",
                })
            end)

            test(bot, {
                update_id = 842537832,
                message = {
                    message_id = 1347,
                    entities = {
                        {
                            type = "bot_command",
                            length = 2,
                            offset = 0,
                        },
                    },
                    date = 1703358174,
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
                    text = "/t",
                },
            },
            function(r) assert.are.same(r, {
                chat_id = 101010101,
                reply_markup = {
                    inline_keyboard = {
                        {
                            {
                                text = "button",
                                callback_data = "Luagram_event_ok",
                            },
                        },
                    },
                },
                parse_mode = "HTML",
                text = "content",
            }) end)

            test(bot, {
                update_id = 842537833,
                callback_query = {
                    data = "Luagram_event_ok",
                    chat_instance = "-6184452786735168277",
                    from = {
                        is_bot = false,
                        first_name = "Lua",
                        id = 101010101,
                        last_name = "gram",
                        language_code = "en",
                        username = "Luagram",
                    },
                    message = {
                        reply_markup = {
                            inline_keyboard = {
                                {
                                    {
                                        callback_data = "Luagram_event_ok",
                                        text = "button",
                                    },
                                },
                            },
                        },
                        message_id = 1348,
                        date = 1703358175,
                        from = {
                            is_bot = true,
                            username = "luagrambot",
                            first_name = "LUAGRAM",
                            id = 202020202,
                        },
                        chat = {
                            first_name = "Lua",
                            id = 101010101,
                            type = "private",
                            username = "Luagram",
                            last_name = "gram",
                        },
                        text = "content",
                    },
                    id = "622150475951426722",
                },
            },
            function(r) assert.truthy(r) end)

        end)

        it("on_ok with argument", function()

            local bot  = new()

            bot:compose("/t"):text("content"):button("button", "ok", 100)

            bot:on_ok(function(update, argument)
                assert.are.same(update, {
                    data = "Luagram_event_ok",
                    chat_instance = "-6184452786735168277",
                    from = {
                        is_bot = false,
                        first_name = "Lua",
                        id = 101010101,
                        last_name = "gram",
                        language_code = "en",
                        username = "Luagram",
                    },
                    message = {
                        reply_markup = {
                            inline_keyboard = {
                                {
                                    {
                                        text = "button",
                                        callback_data = "Luagram_event_ok_100",
                                    },
                                },
                            },
                        },
                        message_id = 1348,
                        date = 1703358175,
                        from = {
                            is_bot = true,
                            username = "luagrambot",
                            first_name = "LUAGRAM",
                            id = 202020202,
                        },
                        chat = {
                            first_name = "Lua",
                            id = 101010101,
                            type = "private",
                            username = "Luagram",
                            last_name = "gram",
                        },
                        text = "content",
                    },
                    id = "622150475951426722",
                })
                print("--->", argument, type(argument))
                assert.True(argument == 100)
            end)

            test(bot, {
                update_id = 842537832,
                message = {
                    message_id = 1347,
                    entities = {
                        {
                            type = "bot_command",
                            length = 2,
                            offset = 0,
                        },
                    },
                    date = 1703358174,
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
                    text = "/t",
                },
            },
            function(r) assert.are.same(r, {
                chat_id = 101010101,
                reply_markup = {
                    inline_keyboard = {
                        {
                            {
                                text = "button",
                                callback_data = "Luagram_event_ok_100",
                            },
                        },
                    },
                },
                parse_mode = "HTML",
                text = "content",
            }) end)

            test(bot, {
                update_id = 842537833,
                callback_query = {
                    data = "Luagram_event_ok",
                    chat_instance = "-6184452786735168277",
                    from = {
                        is_bot = false,
                        first_name = "Lua",
                        id = 101010101,
                        last_name = "gram",
                        language_code = "en",
                        username = "Luagram",
                    },
                    message = {
                        reply_markup = {
                            inline_keyboard = {
                                {
                                    {
                                        callback_data = "Luagram_event_ok_100",
                                        text = "button",
                                    },
                                },
                            },
                        },
                        message_id = 1348,
                        date = 1703358175,
                        from = {
                            is_bot = true,
                            username = "luagrambot",
                            first_name = "LUAGRAM",
                            id = 202020202,
                        },
                        chat = {
                            first_name = "Lua",
                            id = 101010101,
                            type = "private",
                            username = "Luagram",
                            last_name = "gram",
                        },
                        text = "content",
                    },
                    id = "622150475951426722",
                },
            },
            function(r) assert.truthy(r) end)

        end)

end)