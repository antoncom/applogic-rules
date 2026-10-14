local util = require "luci.util"
local checkubus = require "applogic.util.checkubus"
local func_nodes_builder = require "applogic.util.func_nodes_builder"
local perf = require "applogic.util.perf"

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
    local result = {}
    local noerror = true
    local err = ""
    local tmp_res, obj, method, params
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

    if (noerror and type(tmp_res) ~= "table") then
        noerror, err = false, "[load-ubus] must return a table { object, method, params }"
    end

    if (noerror) then

        local cached = tmp_res["cached"] or "yes" -- Allow to user turn OFF caching the node

        --[[ LOAD FROM UBUS ]]
        obj = tostring(tmp_res.object or "")
        method = tostring(tmp_res.method or "")
        params = tmp_res.params or {}

        -- "applogic debug perf": разбивка [load-ubus] на ключ кэша, проверку объекта и сам вызов
        local c0, w0, m0

        -- Ключ кэша - сама строка запроса. Раньше от неё брался md5: на роутере это
        -- стоило ~11 мс CPU за итерацию, а уникальности строки и так достаточно.
        -- Пустые параметры (самый частый случай) не сериализуем.
        if perf.enabled then c0, w0, m0 = perf.start() end
        cache_key = obj .. "\0" .. method .. "\0" .. ((next(params) == nil) and "{}" or util.serialize_json(params))
        if c0 then perf.stop("ubus", "ubus.key", c0, w0, m0) end

        if (rule.cache_ubus[cache_key] and cached ~= "no") then
            -- Такой же запрос уже был на этой итерации: берём ответ из кэша.
            -- Проверка объекта на шине нужна только перед настоящим вызовом.
            result = rule.cache_ubus[cache_key]
        else
            if c0 then c0, w0, m0 = perf.start() end
            noerror, err = checkubus(rule.conn, obj, method)
            if c0 then perf.stop("ubus", "ubus.check", c0, w0, m0) end

            if (noerror) then
                if c0 then c0, w0, m0 = perf.start() end
                local node = rule.conn:call(obj, method, params)
                if c0 then perf.stop("ubus", "ubus.call", c0, w0, m0) end
                rule.cache_ubus[cache_key] = node or { info = "ubus call for [" .. obj .."][".. method .."] returned empty or nil."}
                result = rule.cache_ubus[cache_key]
            else
                result = { error = "ubus object or method not found: [" .. obj .."][".. method .."] failed"}
            end
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