local util = require "luci.util"
local func_nodes_builder = require "applogic.util.func_nodes_builder"
local func_debug = require "applogic.util.func_debug"

-- Оператор [journal] принимает JSON и передаёт его по шине UBUS в сервис Tsmjournal

local function journal(rule, nodename, op_name, op_body)
    local node_debug
    if rule.debug_mode.enabled then node_debug = require "applogic.node.debug" end

    local nodes = func_nodes_builder:make_nodes(rule)

    local result = ""
    local noerror = true
    local tmp_res

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

    result = tmp_res or nil

    local jour_record = {}
    jour_record["journal"] = result or {}
    jour_record["ruleid"] = rule.ruleid

    util.ubus("tsmodem.journal", "send", jour_record)

    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        node_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end
end

return journal