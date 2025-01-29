local debug_mode = require "applogic.debug_mode"
local loadvar = require "applogic.var.loadvar"
local log = require "applogic.util.log"
local util = require "luci.util"

require "applogic.util.split_string"


function rule_init(table, rule_setting, parent)

    function table:load(varname)
        return loadvar(table, varname)
    end

    --[[ Subscription methanism ]]
    ------------------------------
    -- Это используется каждым правилом для реализации источника
    -- загрузки переменных, для которых source.type == "subscribe".
    -- Подмодуль applogic.var.load_subscribed запускает данную функцию
    -- в том случае если в заданную переменную правила необходимо
    -- загружать исходные данные по подписке.
    
    -- function table:subscribe_ubus(ubus_obj, callback, rule, match_msg, match_name)
    --     local sub = {
    --         notify = function(msg, name)
    --             callback(ubus_obj, msg, name, rule, match_msg, match_name)
    --         end
    --     }
    --     print("####### SUBSCRIBE UBUS #########")
    --     print("## " .. ubus_obj .. " callback func: ")
    --     print(callback)
    --     table.conn:subscribe(ubus_obj, sub)

    --     -- we will keep subscribe functions here
    --     -- in order to avoid duplicating of subscribing

    --     return "subscribed"
    -- end

    if not table.setting then
        table.setting = rule_setting

        table.iteration = parent.iteration
        table.ubus = parent.ubus_object
        table.conn = parent.conn
        table.debug_mode = debug_mode   -- It will be overrided automatically when edit rule:make() functiom in the rule file
        table.variterator = 0           -- Counting variables to make them orderd in the "Rule" report

        --local info = debug.getinfo(1,'S');
        --info.source:match("%d+_rule\.lua$"):sub(1,-5)
        
        table.ruleid = debug.getinfo(2, "S").source:match("%d+_rule\.lua"):sub(1,-5)

        table.all_rules = parent.setting.rules_list.target
        
        table.parent = parent
        table.parent:make_subscription(table)
        
    else
        -- Already inited
    end

    table.is_busy = false
    table.cache_ubus = parent.cache_ubus
    table.cache_uci = parent.cache_uci
    table.cache_bash = parent.cache_bash
    table.subscriptions = parent.subscriptions
    


    -- TODO
    -- сделать дебаг только по указанному в UCI правилу
    -- иначе require "applogic.util.report" присоединяется ко всем правилам и замедляет отладку

    --if not table.report and table.debug_mode.enabled then
    if not table.report and table.debug_mode.enabled and table.setting["my_subscribed_var"] then
        table.report = require "applogic.util.report"
        print(string.format("applogic: debug mode enabled for [%s] %s", table.ruleid, table.setting.title.input))
    end

    if table.debug_mode.enabled then
        table.iteration = table.iteration + 1
    end

    return table
end

return rule_init
