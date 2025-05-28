function lua_func(varname, mdf_name, rule)
    local var_debug
    if rule.debug_mode.enabled then var_debug = require "applogic.var.debug" end
    local varlink = rule.setting[varname]
    local func = rule.setting[varname].modifier[mdf_name]
    local from_input = (not varlink.source) and mdf_name:sub(1,1) == "1"

    local vars = {}

    -- logic from util/substitute.lua
    for name, _ in pairs(rule.setting) do
        if name ~= varname then
            vars[name] = rule.setting[name].output
        else
            if from_input then
                vars[name] = rule.setting[name].input
            else
                vars[name] = rule.setting[name].subtotal
            end
        end
    end

    local result = ""
    local noerror = true
    local tmp_res

    if type(func) == "function" then
        noerror, tmp_res = pcall(func, vars)

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
        local func_debug_info = debug.getinfo(func)

        local path_to_func = tostring(func_debug_info.source):match(".*applogic/(.*)")
        local log_info = "path: " .. tostring(path_to_func) .. ":" .. tostring(func_debug_info.linedefined) .. "\n"
        log_info = log_info .. "lines: " .. tostring(func_debug_info.linedefined) .. "-" .. tostring(func_debug_info.lastlinedefined) .. "\n"

        var_debug(varname, rule):modifier(mdf_name, log_info, result, noerror)
    end

    return result
end

return lua_func