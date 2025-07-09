local debug_mode = require "applogic.debug_mode"
local loadvar = require "applogic.operator.loadvar"


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
    end

    table.cache_ubus = parent.cache_ubus
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