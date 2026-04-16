local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"
local func_clear_next_nodes = require "applogic.util.func_clear_next_nodes"

-- operator: break
-- ["break"] = function(vars) <lua code> end
local function func(rule, nodename, op_name, op_body)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.node.debug" end

    local vars = func_vars_builder.make_vars(rule)

    local noerror = true
    local result

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

    if (type(result) == "boolean" and result == true) then
        rule.break_in = true

        -- Очистить значения последующих узлов правила
        -- для того, чтобы после возобновления обработки, не остались старые значния (до break)

        func_clear_next_nodes(rule, nodename)

    else
        rule.break_in = false
    end

    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        var_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end
end

return func