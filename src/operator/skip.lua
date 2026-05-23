local func_nodes_builder = require "applogic.util.func_nodes_builder"
local func_debug = require "applogic.util.func_debug"

-- operator: skip
-- ["skip"] = function(nodes) return <logical expression> end

-- Оператор [skip]=true пропускает обработку следующих за ним операторов узла.

local function skip(rule, nodename, op_name, op_body)
    local node_debug
    if rule.debug_mode.enabled then node_debug = require "applogic.node.debug" end

    local nodes = func_nodes_builder:make_nodes(rule)

    local result = false
    local noerror, tmp_res

    if type(op_body) == "function" then
        noerror, tmp_res = pcall(op_body, nodes)
    else
        result = true -- skip if not a function
        tmp_res = nil
    end

    if tmp_res == nil then
        noerror = false
        result = true -- skip anyway if error in lua chank
    else
        result = tmp_res
    end

    if rule.debug_mode.enabled then
        local output_info

        if type(op_body) == "function" then
            output_info = func_debug.generate_output_info(op_body)
        else
            output_info = "not a function"
        end

        node_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end

    return result
end

return skip