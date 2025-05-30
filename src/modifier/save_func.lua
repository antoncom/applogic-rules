local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"

function save_func(varname, mdf_name, rule)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.var.debug" end
    local varlink = rule.setting[varname]
    local func = rule.setting[varname].modifier[mdf_name]
    local from_input = (not varlink.source) and mdf_name:sub(1,1) == "1"

    local vars = func_vars_builder.make_vars(varname, rule, from_input)

    local result = ""
    local noerror = true
    local tmp_res

    noerror, tmp_res = pcall(func, vars)

    result = tmp_res or ""

    if noerror then
        varlink["saved"] = result
    end

    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(func)
        var_debug(varname, rule):modifier(mdf_name, output_info, result, noerror)
    end

    return result
end

return save_func