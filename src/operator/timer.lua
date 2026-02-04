local uloop = require "uloop"
local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"

local nodelink

local function timer_func()
    if nodelink and nodelink.timer_op.value > 0 then
        nodelink.timer_op.value = nodelink.timer_op.value - 1
        nodelink.timer_op.handler:set(1000)
    end
end

-- operator: timer_op_op
-- ["timer_op"] = function(vars) return <number> end
local function timer_op(rule, nodename, op_name, op_body)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.node.debug" end

    local nodes = func_vars_builder.make_vars(rule)
    local result = 0
    local noerror = true
    local init_value

    nodelink = nodes[nodename]

    if not nodelink.timer_op then

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


        nodelink.timer_op = {
            value = init_value or 0,
            handler = uloop.timer(timer_op_func)
        }
        

        if nodelink.timer_op.value ~= 0 then 
            nodelink.timer_op.handler:set(1000)
        end
    end
        

    result = nodelink.timer_op.value

    
    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        var_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end

    return result
end

return timer_op