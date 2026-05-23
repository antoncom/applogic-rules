local util = require "luci.util"
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local checkubus = require "applogic.util.checkubus"
local func_nodes_builder = require "applogic.util.func_nodes_builder"

-- operator: load-ubus
-- ["load-ubus"] = {
--      object = "object name",
--      method = "method name",
--      params = { empty table or table with params },
--      cached = "yes" (optional),
-- }

-- Оператор [load-ubus] отправляет запрос к системной шине и возвращает в узел полученное значение.
-- Одинаковые запросы к UBUS кэшируются так, что вне зависимости из каких узлов и правил делаются одинаковые запросы,
-- фактически выполяется только один уникальный запрос к UBUS. А остальные дубли - кэшируются.
-- Это снижает нагрузку на шину.

-- Перед новой итераицией обработки правил кэш очищается.

local function load_ubus(rule, nodename, op_name, op_body)
    local debug
    local cache_key = ""
    local cached = ""
    local result
    local noerror = true
    local err = ""
    local nodes = func_nodes_builder:make_nodes(rule)

    if rule.debug_mode.enabled then debug = require "applogic.node.debug" end

    if type(op_body) == "function" then
        noerror, tmp_res = pcall(op_body, nodes)

        if noerror == false then
            print("Error: " .. tostring(tmp_res))
            tmp_res = nil
        end
    else
        tmp_res = nil
        noerror = false
    end


    if (noerror) then

        cached = tmp_res["cached"] or "yes" -- Allow to user turn OFF caching the node
        
        --[[ LOAD FROM UBUS ]]
        obj = string.format("%s", (tmp_res.object or ""))
        method = string.format("%s", (tmp_res.method or ""))
        params = util.clone((tmp_res.params or {}))
        noerror, err = checkubus(rule.conn, obj, method)

        if (noerror) then
            cache_key = md5.sumhexa(obj..method..util.serialize_json(params))

            if ((not rule.cache_ubus[cache_key]) or cached == "no") then
                local node = rule.conn:call(obj, method, params)
                rule.cache_ubus[cache_key] = node or ""
            end

            result = rule.cache_ubus[cache_key] or ""
        end
    end

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