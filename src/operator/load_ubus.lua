local util = require "luci.util"
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local checkubus = require "applogic.util.checkubus"

-- operator: load-ubus
-- ["load-ubus"] = {
--      object = "object name",
--      method = "method name",
--      params = { empty table or table with params },
--      cached = "yes" (optional),
-- }
local function load_ubus(rule, node_name, op_name, op_body)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

    local cache_key = ""
    local cached = op_body["cached"] or "yes" -- Allow to user turn OFF caching the variable
    local result
    local noerror = true
    local err = ""

    --[[ LOAD FROM UBUS ]]
    local obj = string.format("%s", (op_body.object or ""))
    local method = string.format("%s", (op_body.method or ""))
    local params = util.clone((op_body.params or {}))

    --util.dumptable(params)
    -- Substitute values from matched variables
    for par_name, par_value in util.kspairs(params) do
        if(par_name == "match") then
            for match_name, match_value in util.kspairs(params["match"]) do
                params["match"][match_name] = substitute(rule, match_value, false)
            end
        else
            params[par_name] = substitute(rule, par_value, false)
        end
    end

    --cache_key = md5.sumhexa(varname..obj..method..util.serialize_json(params))
    cache_key = md5.sumhexa(obj..method..util.serialize_json(params))

    --if not rule.cache_ubus[cache_key] then
    if ((not rule.cache_ubus[cache_key]) or cached == "no") then
        -- Cache result only if ubus object/method is valid
        noerror, err = checkubus(rule.conn, obj, method)
        if noerror then
            local variable = rule.conn:call(obj, method, params)
            rule.cache_ubus[cache_key] = variable or ""
        end
    end

    result = rule.cache_ubus[cache_key] or ""
    if rule.debug_mode.enabled then
        if (noerror) then
            debug(node_name, rule):source_ubus(obj, method, params, result, noerror, op_body)
        else
            debug(node_name, rule):source_ubus(obj, method, params, err, noerror, op_body)
        end
    end

    return (rule.cache_ubus[cache_key] and util.serialize_json(rule.cache_ubus[cache_key])) or ""
end

return load_ubus