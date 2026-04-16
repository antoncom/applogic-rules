local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"

-- operator: save
-- ["save"] = function(vars) return <value to save> end
local function save(rule, nodename, op_name, op_body)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.node.debug" end

    local nodelink = rule.setting[nodename]
    local vars = func_vars_builder.make_vars(rule)

    local noerror, tmp_res = pcall(op_body, vars)

    local result
    if tmp_res == nil then
        result = ""
    else
        result = tmp_res
    end

    if noerror then
        nodelink["saved"] = result
    end

    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        var_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end

    return result
end

return save