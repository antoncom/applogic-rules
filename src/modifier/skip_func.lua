local func_vars_builder = require "applogic.util.func_vars_builder"
local func_debug = require "applogic.util.func_debug"

function skip_func(varname, rule)
	local var_debug
	if rule.debug_mode.enabled then var_debug = require "applogic.var.debug" end
	local func = rule.setting[varname].modifier and rule.setting[varname].modifier["1_skip-func"] or 'Mistype: always use ["1_skip"] as skip modifier name.'

    local vars = func_vars_builder.make_vars(varname, rule, true)

    local result = false
    local noerror, tmp_res

    if type(func) == "function" then
        noerror, tmp_res = pcall(func, vars)
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

        if type(func) == "function" then
            output_info = func_debug.generate_output_info(func)
        else
            output_info = "not a function"
        end

        var_debug(varname, rule):modifier("1_skip-func", output_info, result, noerror)
	end

	return result
end

return skip_func
