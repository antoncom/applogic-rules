local debug_mode = require "applogic.debug_mode"
local loadvar = require "applogic.var.loadvar"
local log = require "applogic.util.log"

function rule_init(table, rule_setting, parent)

    if not table.setting then
        table.setting = rule_setting
        table.iteration = 0
    end

    table.ubus = {}
    table.debug_mode = debug_mode        -- It will be overrided automatically when edit rule:make() functiom in the rule file
    table.variterator = 0           -- Counting variables to make them orderd in the "Rule" report
    table.ruleid = debug.getinfo(2, "S").source:match("%d+_rule\.lua"):sub(1,-5)

    table.cache_ubus, table.cache_uci, table.cache_bash = {}, {}, {}
    table.is_busy = false


    if not table.report and table.debug_mode.enabled then
        table.report = require "applogic.util.report"
        print(string.format("applogic: debug mode enabled for [%s] %s", table.ruleid, table.setting.title.input))
    end

    if table.debug_mode.enabled then
        table.iteration = table.iteration + 1
    end

    table.ubus = parent.ubus_object
    table.conn = parent.conn

    function table:load(varname)
        return loadvar(table, varname)
    end
    function table:clear_cache()
        table.cache_ubus, table.cache_uci, table.cache_bash = nil, nil, nil
        table.cache_ubus, table.cache_uci, table.cache_bash = {}, {}, {}
    end

    return table
end

return rule_init
