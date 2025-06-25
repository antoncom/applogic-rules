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

    test_node = {
        note = [[ only for test ]],
        modifier = {
            {
                ["func"] = function (vars)
                    print('test text')
                end
            },
        }
    },

    os_time = {
        note = [[ os time ]],
        modifier = {
            {
                ["func"] = function (vars)
                    print('os time:')
                    return os.time()
                end
            },

            {
                ["func"] = function (vars)
                    print(vars.os_time)
                    print("____________________")
                end
            }
        }
    },
}

function rule:make()
    -- todo debug setup
    debug_mode.level = "ERROR"
    rule.debug_mode = debug_mode


    self:load("title")
    self:load("test_node"):modify()
    self:load("os_time"):modify()
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