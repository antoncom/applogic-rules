local debug_mode = require "applogic.debug_mode"
local loadvar = require "applogic.operator.loadvar"
local ev_queue = require "applogic.util.queue"
local util = require "luci.util"


local function rule_init(table, rule_setting, parent)
    function table:follow(nodename)
        return loadvar(table, nodename):run_node()
    end

    -- if the rule is not inited yet
    if not table.setting then
        table.setting = rule_setting
        table.iteration = parent.iteration
        table.ubus = parent.ubus_object
        table.conn = parent.conn
        table.debug_mode = debug_mode   -- It will be overrided automatically when edit rule:make() functiom in the rule file
        table.variterator = 0           -- Counting variables to make them orderd in the "Rule" report
        table.ruleid = debug.getinfo(2, "S").source:match("%d+_rule\.lua"):sub(1,-5)
        table.all_rules = parent.setting.rules_list.target
        table.parent = parent
        table.parent:make_subscription(table)


        -- проверка событий на соответствие match (для оператора [subscribe])
        function check_match(pattern, evmsg)
            local msg_matched = false

            if ((not pattern) or #util.keys(pattern) == 0) then 
                msg_matched = true
            else
                for attr,value in util.kspairs(pattern) do
                    if (evmsg[attr] and evmsg[attr] == value) then
                        msg_matched = true
                        break
                    end
                end
            end
            return msg_matched
        end

        -- Подготовить очередь и методы узла для обработи входящих событий

        for _, node in util.kspairs(table.setting) do
            for _, operator in ipairs(node) do
                if (operator["subscribe"]) then
                    
                   node["queue"] = ev_queue:new()
                   local queue = node["queue"]
                    
                    -- метод добавления данных события в очередь на загрузку в узел
                    function node:enqueue(evname, evmsg)
                        if( (operator["subscribe"]["evname"] == evname) and check_match(operator["subscribe"]["match"], evmsg) ) then
                                -- Добавляем вновь поступившее событий в очередь на загрузку в узел
                                local qitem = {
                                    ["evname"] = evname,
                                    ["evmsg"] = evmsg
                                }
                                queue:enqueue(qitem)
                        end
                    end

                    function node:dequeue(evname, evmsg)
                        return queue:dequeue()
                    end

                    function node:queueIsEmpty()
                        return queue:isEmpty()
                    end


                    break

                end
            end
        end


    end

    table.cache_ubus = parent.cache_ubus
    table.subscriptions = parent.subscriptions

    --[[ 
        Оператор [break] - если он сработал в каком-то узле,
        отменяет обработку всех последующих узлов правила.

        Для этого служит флаг rule.break_in.

        Если break_in установлен в true, то обрабтка очередного узла отменяется.

        В начале новой итерации - флаг сбрасывается.
    ]]
    table.break_in = false

    

    -- TODO
    -- сделать дебаг только по указанному в UCI правилу
    -- иначе require "applogic.util.report" присоединяется ко всем правилам и замедляет отладку

    --if not table.report and table.debug_mode.enabled then
    if not table.report and table.debug_mode.enabled and table.setting["my_subscribed_var"] then
        table.report = require "applogic.util.report"
        print(string.format("applogic: debug mode enabled for [%s] %s", table.ruleid, table.setting.title.input))
    end

    -- if table.debug_mode.enabled then
    --     table.iteration = table.iteration + 1
    -- end

    return table
end

return rule_init