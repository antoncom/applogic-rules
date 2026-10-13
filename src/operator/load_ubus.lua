local util = require "luci.util"
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
    local result = {}
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
            -- Ключ кэша - сама строка запроса. Раньше от неё брался md5: на роутере это
            -- стоило ~11 мс CPU за итерацию, а уникальности строки и так достаточно.
            cache_key = obj .. "\0" .. method .. "\0" .. util.serialize_json(params)

            if ((not rule.cache_ubus[cache_key]) or cached == "no") then
                local node = rule.conn:call(obj, method, params)
                rule.cache_ubus[cache_key] = node or { info = "ubus call for [" .. obj .."][".. method .."] returned empty or nil."}
            end

            result = rule.cache_ubus[cache_key] or { error = "ubus data not found in cache: [" .. obj .."][".. method .."] failed"}
        else
            result = { error = "ubus object or method not found: [" .. obj .."][".. method .."] failed"}
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