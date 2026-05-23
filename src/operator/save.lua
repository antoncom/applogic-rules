local func_nodes_builder = require "applogic.util.func_nodes_builder"
local func_debug = require "applogic.util.func_debug"

-- operator: save
-- ["save"] = function(nodes) return <value to save> end

-- Т.к. перед началом новой итерации обработки правил все узлы очищаются, то
-- оператор [save] сохраняет значение узла для использования в следующей итерации

local function save(rule, nodename, op_name, op_body)
    local node_debug
    if rule.debug_mode.enabled then node_debug = require "applogic.node.debug" end

    local nodelink = rule.setting[nodename]
    local nodes = func_nodes_builder:make_nodes(rule)

    local noerror, tmp_res = pcall(op_body, nodes)

    local result
    if tmp_res == nil then
        result = ""
    else
        result = tmp_res
    end

    if noerror then
        nodelink["saved"] = result
    end

    if rule.debug_mode.enabled then
        local output_info = func_debug.generate_output_info(op_body)
        node_debug(nodename, rule):operator(op_name, output_info, result, noerror)
    end

    return result
end

return save