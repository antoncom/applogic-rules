local util = require "luci.util"

local uloop = require "uloop"
local func_nodes_builder = require "applogic.util.func_nodes_builder"
local func_debug = require "applogic.util.func_debug"

--[[
rule.timers = {
    [nodename] = {
        inited = <init_value>,
        value = <count_value>,
        handler = <timer_func>
    }
}
]]
-- operator: timeout
-- ["timeout"] = function(nodes) return <number> end

-- Оператор [timeout] создаёт стстемный таймер обратного отсчёта.

local function timeout(rule, nodename, op_name, op_body)
    local node_debug
    if rule.debug_mode.enabled then node_debug = require "applogic.node.debug" end

    local nodes = func_nodes_builder:make_nodes(rule)
    local result = {
        inited = 0,
        value = 0
    }
    local noerror = true
    local init_value

    --[[
        Функция запускается 1 раз в секунду и уменьшает значение таймера на 1 сек.
        По достижении 0, функция перестает запускать сама себя.
    ]]
    local function timer_func()
        if rule.timers[nodename] and tonumber(rule.timers[nodename].value) and rule.timers[nodename].value >= 0 then
            rule.timers[nodename].value = rule.timers[nodename].value - 1
            rule.timers[nodename].handler:set(1000)
        end
    end

    --[[
        При обработке оператора [timeout] на каждой итерации работы правила
        в узел возвращается текущее значение таймера
    ]]
    if type(op_body) == "function" then
        noerror, init_value = pcall(op_body, nodes)

        if noerror == false then
            print("Error: " .. tostring(init_value))
            init_value = nil
        end
    else
        init_value = nil
        noerror = false
    end
    
    -- При первом выполнении оператора [timeout]
    -- создаётся структура в текущем правиле

    if not rule.timers then 
        rule.timers = {} 
    end

    -- Если таймер ещё не создан - инициализируем

    if not rule.timers[nodename] then
        rule.timers[nodename] = {
            inited = init_value or 0,
            value = init_value or 0,
            handler = uloop.timer(timer_func)
        }
        rule.timers[nodename].handler:set(1000)
    end


    -- если таймер достиг 0 - удаляем его из структуры таймеров
    -- с тем, чтобы на новой итерации он при необходимости был вновь инициализирован первичными значениями

    if rule.timers[nodename] and tonumber(rule.timers[nodename].value) and rule.timers[nodename].value < 0 then
        result.value = tonumber(rule.timers[nodename].inited)
        result.inited = tonumber(rule.timers[nodename].inited)
        -- Удаляем объект таймаут, если он окончен
        rule.timers[nodename] = rule.timers[nodename] and nil
    else
        result.value = rule.timers[nodename].value
        result.inited = rule.timers[nodename].inited    
    end

    -- TODO
    -- при изменении Timeout в веб-интерфейсе (панель "Настройка сим-карт")
    -- надо чтобы текущий порог (init_value) автоматически обновляся
    -- т.к. сейчас таймер продолжает достигать начально загруженного порога

    
    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        node_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end

    return result
end

return timeout