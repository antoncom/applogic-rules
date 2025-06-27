--[[
Test rule, only for test new rules design
--]]

local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"

local rule = {}

local rule_setting = {
    title = {
        input = "Test rule",
    },

    test_skip = {
        note = [[ test skip ]],
        modifier = {
            {
                ["func"] = function (vars)
                    print('text before skip operator')
                end
            },

            {
                ["skip"] = function (vars)
                    return true
                end
            },

            {
                ["func"] = function (vars)
                    print("text after skip operator")
                end
            }
        }
    },

    test_bash = {
        title = [[ test bash ]],
        modifier = {
            {
                ["func"] = function (vars)
                    return [[{"value": "text from json"}]]
                end
            },

            {
                ["bash"] = [[ jsonfilter -e $.value ]]
            },

            {
                ["func"] = function (vars)
                    print('parsed value: ' .. (vars.subtotal or ""))
                end
            },
        }
    },

    test_save = {
        title = [[ test save ]],
        modifier = {
            {
                ["save"] = function ()
                    return 10
                end
            }
        },
    },

    test_frozen = {
        title = [[ test frozen ]],
        modifier = {
            {
                ["frozen"] = function ()
                    -- return 5 -- frozen time (seconds)
                    return {
                        5, -- frozen time (seconds)
                        os.time() % 100 -- value after frozen
                    }
                end
            }
        },
    },

    test_ui_update = {
        title = [[ test ui update ]],
        modifier = {
            {
                ["ui-update"] = {
                    param_list = {
                        "test_bash",
                    }
                },
            }
        },
    },

    test_store_db = {
        title = [[ test store db ]],
        modifier = {
            {
                ["store-db"] = {
                    param_list = { "journal" }
                },
            },
        }
    },
}

function rule:make()
    -- todo debug setup
    debug_mode.level = "ERROR"
    rule.debug_mode = debug_mode

    self:load("title")

    print('\n\n\n')
    print('---------------------------------------------')


    print('> test skip:')
    self:load("test_skip"):modify()

    print('\n> test bash:')
    self:load("test_bash"):modify()

    print('\n> test save:')
    self:load("test_save"):modify()
    print('saved value: ' .. tostring(rule_setting.test_save["saved"]))

    print('\n> test frozen:')
    self:load("test_frozen"):modify()
    local frozen_table = rule_setting.test_frozen["frozen"]
    if type(frozen_table) == "table" then
        print('value: ' .. tostring(frozen_table["value"]))
        print('seconds: ' .. tostring(frozen_table["seconds"]))
        print('cancel_time: ' .. tostring(frozen_table["cancel_time"]))
        print('value_after: ' .. tostring(frozen_table["value_after"]))
        print('rule_setting.test_frozen["subtotal"]: ' .. tostring(rule_setting.test_frozen["subtotal"]))
    else
        print("no frozen table found")
    end

    print('\n> test ui-update:')
    self:load("test_ui_update"):modify()

    print('\n> test store db:')
    self:load("test_store_db"):modify()
    print('\n> test_store_db node called')

    print('---------------------------------------------')
end

local metatable = {
    __call = function(table, parent)
        local rule_init_table = rule_init(table, rule_setting, parent)
        rule_init_table:make()
        return rule_init_table
    end
}
setmetatable(rule, metatable)
return rule