local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"

-- operator: func
-- ["func"] = function(vars) <lua code> end
local function func(rule, node_name, op_name, op_body, op_index)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.var.debug" end

    local node_table = rule.setting[node_name]
    local from_input = (not node_table.source) and (op_index == 1)
    local vars = func_vars_builder.make_vars(node_name, rule, from_input)

    local result = ""
    local noerror = true
    local tmp_res

    if type(op_body) == "function" then
        noerror, tmp_res = pcall(op_body, vars)

        if noerror == false then
            print("Error: " .. tostring(tmp_res))
            tmp_res = nil
        end
    else
        tmp_res = nil
        noerror = false
    end

    result = tmp_res or ""

    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        var_debug(node_name, rule):modifier(op_name, output_info, result, noerror)
    end

    return result
end

return func