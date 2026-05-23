local util = require "luci.util"

local skip = require "applogic.operator.skip"
local func = require "applogic.operator.func"
local bash = require "applogic.operator.bash"
local save = require "applogic.operator.save"
local frozen = require "applogic.operator.frozen"
local load_ubus = require "applogic.operator.load_ubus"
local load_subscribed = require "applogic.operator.load_subscribed"
local journal = require "applogic.operator.journal"
local websocket = require "applogic.operator.websocket"
local break_op = require "applogic.operator.break"
local timeout = require "applogic.operator.timeout"

-- Обрабатываем последовательно все операторы узла.
-- Если встречается оператор [break]=true, прерываем обработку правила.
-- Если встречается оператор [skip]=true, прерываем обрабтку операторов узла, следующих за [skip].
-- Если в узле сработал оператор [frozen], то откладываем повторную обработку данного узла на заданное кол-во секунд.
-- Если в узле сработал оператор [save], то перед началом новой итерации загружаем в узел значение, сохранённое на предыдущей итерации.

local main = {}
function main:run_node(nodename, rule)
    -- Отменяем обработку узла, если где-то в данном правиле сработал оператор [break]
    if (rule.break_in) then return end

    local debug
    local nodelink = rule.setting[nodename]

    if nodelink["saved"] then
        nodelink.output = nodelink["saved"]
    elseif nodelink["frozee"] then
        nodelink.output = tostring(nodelink["frozee"])
    elseif nodelink["default"] then
        nodelink.output = tostring(nodelink["default"])
    else
        nodelink.output = ""
    end

    if rule.debug_mode.enabled then
        debug = require "applogic.node.debug"
        debug:clear_operators()
    end

    for _, operator_table in ipairs(nodelink) do
        local operator_name, operator_body

        -- operator_table: { ["op_name"] = <op_body> }
        for key, value in pairs(operator_table) do
            operator_name = key
            operator_body = value
        end

        if not (nodelink.frozen) then
            if "skip" == operator_name then
                local is_skip = skip(rule, nodename, operator_name, operator_body)

                if is_skip then
                    break
                end
            elseif "func" == operator_name then
                nodelink.output = func(rule, nodename, operator_name, operator_body)
            elseif "bash" == operator_name then
                nodelink.output = bash(rule, nodename, operator_name, operator_body)

            elseif "save" == operator_name then
                nodelink.output = save(rule, nodename, operator_name, operator_body)

            elseif "load-ubus" == operator_name then
                nodelink.output = load_ubus(rule, nodename, operator_name, operator_body)

            elseif "load-rule" == operator_name then
                nodelink.output = load_rule(rule, nodename, operator_name, operator_body)

            elseif "subscribe" == operator_name then
                load_subscribed(rule, nodename, operator_name, operator_body)

            elseif "ui-update" == operator_name then
                websocket(rule, nodename, operator_name, operator_body)

            elseif "journal" == operator_name then
                journal(rule, nodename, operator_name, operator_body)
            
            elseif "timeout" == operator_name then
                nodelink.output = timeout(rule, nodename, operator_name, operator_body)
            end
        end

        if "frozen" == operator_name then
            frozen(rule, nodename, operator_name, operator_body)
        end

        if "break" == operator_name then
            break_op(rule, nodename, operator_name, operator_body)
            if rule.break_in and rule.break_in == true then
                break
            end
        end
    end

    if rule.debug_mode.enabled then debug(nodename, rule):output(nodelink.output) end
end

return main