-- Очищаем значения узлов, следующих за данным
-- Это часто используется при выполнении таких операторов, как [break]:
-- прерывая дальнейшую обработку правила, важно очистить последующие узлы 
-- от заведомо устаревающих данных.

-- В протианом случае, если на какой-то очередной итерации данный [break] не выполнится,
-- обработка узлов правила продолжится, но в них могут находится устаревшие данные, сохранённые, например
-- оператором [save] или [timeout].

-- В случае с [timeout] проблема наблюдалась при передаче в веб-интерфейс: когда устаревший таймер "застыл",
-- будучи отменённым предыдущим [break], т.е. данные в нём сохранялись несмортя на [break]

function func_clear_next_nodes(rule, nodename)
    local current_node_order = rule.setting[nodename].order

    for name, node in pairs(rule.setting) do
        if node.order and node.order > current_node_order then
            
            if node.saved then
                node.saved = nil
            end

            if node.output then
                node.output = nil
            end

            if node.timer_op then
                node.timer_op = nil
            end

            if rule.timers then
                rule.timers[name] = rule.timers[name] and nil
            end
        end
    end
end

return func_clear_next_nodes