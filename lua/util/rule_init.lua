local debug_mode = require "applogic.debug_mode"
local loadvar = require "applogic.var.loadvar"
local log = require "applogic.util.log"


function rule_init(table, rule_setting, parent)

    if not table.setting then
        table.setting = rule_setting
    end

    table.ubus = {}
    table.report = {}		        -- Populated automatically in debug mode only
    table.debug = debug_mode        -- It will be overrided automatically when edit rule:make() functiom in the rule file
    table.variterator = 0           -- Counting variables to make them orderd in the "Rule" report


    table.cache_ubus, table.cache_uci, table.cache_bash = {}, {}, {}
    table.is_busy, table.iteration = false, 0


    if table.debug.enabled then
        --print(string.format("applogic: Rule [1_rule] includes applogic.util.report for debugging needs in %s mode.", table.debug.type))
        table.report = require "applogic.util.report"
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
