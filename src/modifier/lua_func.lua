local substitute = require "applogic.util.substitute"
local pcallchunk = require "applogic.util.pcallchunk"
local util = require "luci.util"

function lua_func(varname, mdf_name, rule)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
    local varlink = rule.setting[varname]
    local result = ""
    local noerror = true
    local func = rule.setting[varname].modifier[mdf_name]
    local tmp_res

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

    if type(func) == "function" then
        noerror, tmp_res = pcall(func, vars)

        if noerror == false then
            print('Error: ' .. tostring(tmp_res))
            tmp_res = nil
        end
    else
        tmp_res = nil
        noerror = false
    end

    result = tmp_res or ""

    if rule.debug_mode.enabled then
        -- todo
    end

    return result
end

return lua_func