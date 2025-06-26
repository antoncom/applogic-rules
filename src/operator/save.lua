local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"

-- operator: save
-- ["save"] = function(vars) return <value to save> end
local function save(rule, node_name, op_name, op_body, op_index)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.var.debug" end

    local node_table = rule.setting[node_name]
    local from_input = (not node_table.source) and (op_index == 1)
    local vars = func_vars_builder.make_vars(node_name, rule, from_input)

    local noerror, tmp_res = pcall(op_body, vars)
    local result = tmp_res or ""

    if noerror then
        node_table["saved"] = result
    end

    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        var_debug(node_name, rule):modifier(op_name, output_info, result, noerror)
    end

    return result
end

return save