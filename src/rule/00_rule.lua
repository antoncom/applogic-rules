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

    test_ubus = {
        note = [[ test ubus ]],

        {
            ["load-ubus"] = {
                object = "tsmodem.driver",
                method = "reg",
                params = {},
            }
        },

        {
            ["func"] = function (vars)
                print(vars.subtotal)
                return 'test string (returned via func operator in test_ubus node)'
            end
        }
    },

    test_load_rule = {
        note = [[ test load ]],

        {
            ["load-rule"] = {
                rulename = "00_rule",
                varname = "test_ubus",
            }
        },

        {
            ["func"] = function (vars)
                print(vars.subtotal)
            end
        }
    },

    test_subscribe = {
        note = [[ test subscribe ]],

        {
            ["subscribe"] = {
                ubus = "network.interface",
                evname = "interface.update",
                match = { interface = "modem"}
            }
        },

        {
            ["func"] = function (vars)
                print(vars.subtotal)
            end
        },
    },
}


function rule:make()
    -- todo debug setup
    debug_mode.level = "ERROR"
    rule.debug_mode = debug_mode

    self:load("title")

    print('\n\n\n')
    print('------------------------------------------------------------------------------------------')


    print('> test ["load-ubus"] operator:')
    self:load("test_ubus"):modify()

    print('> test ["load-rule"] operator:')
    self:load("test_load_rule"):modify()

    print('> test ["subscribe"] operator:')
    self:load("test_subscribe"):modify()

    print('------------------------------------------------------------------------------------------')
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