local util = require "luci.util"

local uloop = require "uloop"
local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"

--[[
rule.timers = {
    [nodename] = {
        inited = <init_value>,
        value = <count_value>,
        handler = <timer_func>
    }
}
]]


-- operator: timer_op_op
-- ["timer_op"] = function(vars) return <number> end
local function timer_op(rule, nodename, op_name, op_body)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.node.debug" end

    local nodes = func_vars_builder.make_vars(rule)
    local result = {
        inited = 0,
        value = 0
    }
    local noerror = true
    local init_value

    local function timer_func()
        if rule.timers[nodename] and tonumber(rule.timers[nodename].value) and rule.timers[nodename].value >= 0 then
            rule.timers[nodename].value = rule.timers[nodename].value - 1
            rule.timers[nodename].handler:set(1000)
        end
    end

    -- Загружаем исходное значение таймера
    -- если первый раз, либо если таймер равен 0
    --if (not (rule.timers and rule.timers[nodename])) or (rule.timers and rule.timers[nodename] and rule.timers[nodename].value <= 0) then

        if type(op_body) == "function" then
            noerror, init_value = pcall(op_body, nodes)

            if noerror == false then
                print("Error: " .. tostring(init_value))
                init_value = nil
            end
        else
            init_value = nil
            noerror = false
        end
    --end

    if not rule.timers then 
        rule.timers = {} 
    end

    if not rule.timers[nodename] then
        rule.timers[nodename] = {
            inited = init_value or 0,
            value = init_value or 0,
            handler = uloop.timer(timer_func)
        }
        rule.timers[nodename].handler:set(1000)
    end
    

    if rule.timers[nodename] and tonumber(rule.timers[nodename].value) and rule.timers[nodename].value < 0 then
        rule.timers[nodename].value = init_value
        rule.timers[nodename].handler:set(1000)
    end

        
    result.value = rule.timers[nodename].value
    result.inited = rule.timers[nodename].inited

    
    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        var_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end

    return result
end

return timer_op