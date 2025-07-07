local util = require "luci.util"
local skip = require "applogic.operator.skip"
local func = require "applogic.operator.func"
local bash = require "applogic.operator.bash"
local save = require "applogic.operator.save"
local frozen = require "applogic.operator.frozen"
local load_ubus = require "applogic.operator.load_ubus"
local load_rule = require "applogic.operator.load_rule"
local load_subscribed = require "applogic.operator.load_subscribed"
local store_db = require "applogic.operator.store_db"
local ui_update = require "applogic.operator.ui_update"


local main = {}
function main:run_node(node_name, rule)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end
    local node_table = rule.setting[node_name]

    if node_table["saved"] then
        node_table.output = tostring(node_table["saved"])
    elseif node_table["frozee"] then
        node_table.output = tostring(node_table["frozee"])
    elseif node_table["default"] then
        node_table.output = tostring(node_table["default"])
    else
        node_table.output = ""
    end

    for operator_index, operator_table in ipairs(node_table) do
        local operator_name, operator_body

        -- operator_table: { ["op_name"] = <op_body> }
        for key, value in pairs(operator_table) do
            operator_name = key
            operator_body = value
        end

        if not node_table.frozen  then
            if "skip" == operator_name then
                local is_skip = skip(rule, node_name, operator_name, operator_body)

                if is_skip then
                    -- Если указать у переменной default = "some value"
                    -- то перед отменой обработки присвоить переменной значение из input
                    -- иначе в переменной останется хранится последнее расчётное значение (из output)
                    if rule["default"][node_name].default then
                        node_table.default = string.format("%s", rule["default"][node_name].default)
                        node_table.output = string.format("%s",node_table.default)
                    else
                        node_table.output = string.format("%s",node_table.output)
                    end
                    break
                end
            end

            if "func" == operator_name then
                node_table.output = func(rule, node_name, operator_name, operator_body)
            end

            if "bash" == operator_name then
                node_table.output = bash(rule, node_name, operator_name, operator_body)
            end

            if "save" == operator_name then
                node_table.output = save(rule, node_name, operator_name, operator_body)
            end

            if "load-ubus" == operator_name then
                node_table.output = load_ubus(rule, node_name, operator_name, operator_body)
            end

            if "load-rule" == operator_name then
                node_table.output = load_rule(rule, node_name, operator_name, operator_body)
            end

            if "subscribe" == operator_name then
                load_subscribed(rule, node_name, operator_name, operator_body)
            end

            if "ui-update" == operator_name then
                ui_update(rule, node_name, operator_name, operator_body)
            end

            if "store-db" == operator_name then
                store_db(rule, node_name, operator_name, operator_body)
            end
        end

        if "frozen" == operator_name then
            frozen(rule, node_name, operator_name, operator_body)
        end
    end

    if(type(node_table.output) == "table") then
        node_table.output = util.serialize_json(node_table.output)
    else
        node_table.output = string.format("%s", node_table.output)
        local _, n = node_table.output:gsub("\n", "\n")
        if n == 1 then node_table.output = node_table.output:gsub("%s+$", "") end
    end

    if rule.debug_mode.enabled then debug(node_name, rule):output(node_table.output) end
end

return main