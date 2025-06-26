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
    }
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
    print('saved value: ' .. (rule_setting.test_save["saved"] or ""))


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