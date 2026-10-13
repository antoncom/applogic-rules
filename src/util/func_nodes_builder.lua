-- Возвращает узлы указанного правила: nodes.<имя_узла> == rule.setting[<имя_узла>].output
--
-- Раньше перед КАЖДЫМ оператором строилась новая таблица - копия output всех узлов правила
-- (около 150 копий за итерацию). Теперь у правила одна постоянная таблица-"окно":
-- значение узла читается в момент обращения nodes.X, поэтому оно всегда актуально,
-- а лишних таблиц не создаётся.
--
-- Запись в nodes не поддерживается (раньше она терялась после выхода из оператора):
-- результат оператора нужно возвращать через return.

local func_nodes_builder = {}

function func_nodes_builder:make_nodes(rule)
    local proxy = rule.__nodes_proxy
    if not proxy then
        proxy = setmetatable({}, {
            __index = function(_, name)
                local node = rule.setting[name]
                return node and node.output
            end,
            __newindex = function(_, name)
                error("applogic: nodes is read-only (attempt to set nodes." .. tostring(name) .. ")", 2)
            end,
        })
        rule.__nodes_proxy = proxy
    end
    return proxy
end

return func_nodes_builder
