local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"

-- operator: func
-- ["func"] = function(vars) <lua code> end
local function func(rule, nodename, op_name, op_body)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.node.debug" end

    local vars = func_vars_builder.make_vars(rule)

    local result
    local noerror = true

    if type(op_body) == "function" then
        noerror, result = pcall(op_body, vars)

        if noerror == false then
            print("Error: " .. tostring(result))
            result = nil
        end
    else
        result = nil
        noerror = false
    end

    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        var_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end

    return result
end

return func