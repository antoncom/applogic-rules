local func_vars_builder = require "applogic.util.func_vars_builder"

function skip_func(varname, rule)
	local var_debug
	if rule.debug_mode.enabled then var_debug = require "applogic.var.debug" end
	local func = rule.setting[varname].modifier and rule.setting[varname].modifier["1_skip-func"] or 'Mistype: always use ["1_skip"] as skip modifier name.'

    local vars = func_vars_builder.make_vars(varname, rule, true)

    local result = false
    local noerror, tmp_res

    if(type(func) == "function") then
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
        local log_info

        if type(func) == "function" then
            local func_debug_info = debug.getinfo(func)
            local path_to_func = tostring(func_debug_info.source):match(".*applogic/(.*)")
            log_info = "path: " .. tostring(path_to_func) .. ":" .. tostring(func_debug_info.linedefined) .. "\n"
            log_info = log_info .. "lines: " .. tostring(func_debug_info.linedefined) .. "-" .. tostring(func_debug_info.lastlinedefined) .. "\n"
        else
            log_info = "not a function"
        end

        var_debug(varname, rule):modifier("1_skip-func", log_info, result, noerror)
	end

	return result
end

return skip_func
