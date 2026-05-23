local func_nodes_builder = require "applogic.util.func_nodes_builder"
local func_debug = require "applogic.util.func_debug"

-- operator: func
-- ["func"] = function(nodes) <lua code> end
local function func(rule, nodename, op_name, op_body)
    local node_debug
    if rule.debug_mode.enabled then node_debug = require "applogic.node.debug" end

    local nodes = func_nodes_builder:make_nodes(rule)

    local result
    local noerror = true

    if type(op_body) == "function" then
        noerror, result = pcall(op_body, nodes)

        if noerror == false then
            print("Error: " .. tostring(result))
            result = nil
        end
    else
        result = nil
        noerror = false
    end

    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        var_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end

    return result
end

return func