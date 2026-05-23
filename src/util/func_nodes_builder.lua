
-- Возвращает узлы указанного правила

local func_nodes_builder = {}

function func_nodes_builder:make_nodes(rule)
    local nodes = {}

    for name, _ in pairs(rule.setting) do
        nodes[name] = rule.setting[name].output
    end

    return nodes
end

return func_nodes_builder