local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"

-- operator: skip
-- ["skip"] = function(vars) return <logical expression> end
local function skip(rule, node_name, op_name, op_body)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.var.debug" end

    local vars = func_vars_builder.make_vars(rule)

    local result = false
    local noerror, tmp_res

    if type(op_body) == "function" then
        noerror, tmp_res = pcall(op_body, vars)
    else
        result = true -- skip if not a function
        tmp_res = nil
    end

    if tmp_res == nil then
        noerror = false
        result = true -- skip anyway if error in lua chank
    else
        result = tmp_res
    end

    if rule.debug_mode.enabled then
        local output_info

        if type(op_body) == "function" then
            output_info = func_debug.generate_output_info(op_body)
        else
            output_info = "not a function"
        end

        var_debug(node_name, rule):operator(op_name, output_info, result, noerror)
    end

    return result
end

return skip