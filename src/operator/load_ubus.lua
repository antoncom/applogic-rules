local util = require "luci.util"
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local checkubus = require "applogic.util.checkubus"
local func_vars_builder = require "applogic.util.func_vars_builder"

-- operator: load-ubus
-- ["load-ubus"] = {
--      object = "object name",
--      method = "method name",
--      params = { empty table or table with params },
--      cached = "yes" (optional),
-- }
local function load_ubus(rule, nodename, op_name, op_body)
    local debug
    local cache_key = ""
    local cached = ""
    local result
    local noerror = true
    local err = ""
    local vars = func_vars_builder.make_vars(rule)

    if rule.debug_mode.enabled then debug = require "applogic.node.debug" end

    if type(op_body) == "function" then
        noerror, tmp_res = pcall(op_body, vars)

        if type(tmp_res) == "table" then
            luci.util.dumptable(tmp_res)
        else
            print(tostring(tmp_res))
        end

        if noerror == false then
            print("Error: " .. tostring(tmp_res))
            tmp_res = nil
        end
    else
        tmp_res = nil
        noerror = false
    end


    if (noerror) then

        cached = tmp_res["cached"] or "yes" -- Allow to user turn OFF caching the variable
        
        --[[ LOAD FROM UBUS ]]
        obj = string.format("%s", (tmp_res.object or ""))
        method = string.format("%s", (tmp_res.method or ""))
        params = util.clone((tmp_res.params or {}))
        noerror, err = checkubus(rule.conn, obj, method)

        if (noerror) then
            cache_key = md5.sumhexa(obj..method..util.serialize_json(params))

            if ((not rule.cache_ubus[cache_key]) or cached == "no") then
                local variable = rule.conn:call(obj, method, params)
                rule.cache_ubus[cache_key] = variable or ""
            end

            result = rule.cache_ubus[cache_key] or ""
        end
    end

print(obj .. method .. tostring(params), tostring(result))
    if rule.debug_mode.enabled then
        if (noerror) then
            debug(nodename, rule):operator_ubus(obj, method, params, result, noerror, op_body)
        else
            debug(nodename, rule):operator_ubus(obj, method, params, err, noerror, op_body)
        end
    end

    return rule.cache_ubus[cache_key] or {}
end

return load_ubus