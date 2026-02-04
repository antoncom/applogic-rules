local debug_cli = require "applogic.node.debug_cli"
local util = require "luci.util"
local substitute = require "applogic.util.substitute"
local pcallchunk = require "applogic.util.pcallchunk"
-- Moved here (see below)
local operator_handler = require "applogic.operator.main"


local loadvar = {}
local loadvar_metatable = {
    __call = function(loadvar_metatable, rule, nodename)
        local debug
        -- Turn debug mode ON for this rule
        --rule.debug_mode.enabled = (debug_cli.rule and debug_cli.rule == rule.ruleid) or rule.debug_mode.enabled
        if(debug_cli.rule and debug_cli.rule == rule.ruleid) then
            rule.debug_mode.level = "INFO"
        end
        if rule.debug_mode.enabled then
            debug = require "applogic.node.debug"
        end

        --[[ Make default var.input untouched
            as we need initial input value on every iteration of rules operating
        ]]
        -- create default rule setting table
        if (not rule["default"]) then
            rule["default"] = {}
        end

        -- remove source, note, modifier from the default var table
        -- only "input" has to exist in the "default" var setting table
        if (not rule["default"][nodename]) then
            rule["default"][nodename] = util.clone(rule.setting[nodename])
            if rule["default"][nodename].source then rule["default"][nodename].source = nil end
            if rule["default"][nodename].note then rule["default"][nodename].note = nil end
            if rule["default"][nodename].modifier then rule["default"][nodename].modifier = nil end
        end

        -- Also we keep there "overview" debug info if the variable was chosen for this
        -- See below in the debug place

        --local operator_handler = require "applogic.operator.main"
        -- MOVED ABOVE 28.01.2026
        local nodelink = rule.setting[nodename]

        -- Make variable order
        rule.variterator = rule.variterator + 1
        nodelink.order = rule.variterator

        if rule.debug_mode.enabled then debug(nodename, rule):order() end
        if rule.debug_mode.enabled then debug(nodename, rule):note(nodelink.note or "") end
        if rule.debug_mode.enabled then debug(nodename, rule):input(nodelink.input or nodelink.default or "") end

        --[[ Make function chaining in order to use the laconic way in the rule files ]]
        -- rule:load("title"):execute()
        ---------------------=========
        local op = {}
        function op:run_node()
            operator_handler:run_node(nodename, rule)

            -- rule:load("title"):execute():debug()
            ------------------------------========
            local dbg = {}
            function dbg:debug(...)
                local level = arg[1]
                local report_by_cli = (debug_cli.rule and debug_cli.rule == rule.ruleid)
                local overview_by_cli = (debug_cli.rule and debug_cli.rule == "overview")

                --[[ В режиме debug для правила будем показывать также debug для переменной 
                     в том случае, если при её обработке возникла ошибка.
                     Это поможет сразу выводить в консоль таблицу дебага переменной.
                ]]
                local error_in_var = rule and rule.debug and rule.debug.variables[nodename] and (rule.debug.variables[nodename].noerror == false)

                if report_by_cli then -- debug var by CLI like this: "applogic debug 01_rule sim_id"
                    if (error_in_var or util.contains(debug_cli.showvar, nodename)) then
                         rule.debug.report(rule):print_var(nodename, "INFO", rule.iteration)
                    end
                elseif overview_by_cli then
                    if (type(level) == "table") then
                        local overview_vars_for_this_rule = util.keys(level)
                        rule["default"]["overviewed_vars"] = util.clone(overview_vars_for_this_rule)
                        if (util.contains(overview_vars_for_this_rule, nodename)) then
                            if(type(level[nodename]) == "string") then
                                rule.debug.variables[nodename].overview = level[nodename]
                            elseif(type(level[nodename]) == "table") then
                                -- realize colorizing policy of overview report according to subsituted value
                                rule.debug.variables[nodename].overview = {}
                                if(level[nodename].yellow) then
                                    local luacode = substitute(rule, level[nodename].yellow, true)
                                    local noerror
                                    noerror, level[nodename].yellow = pcallchunk(luacode)
                                    rule.debug.variables[nodename].overview["yellow"] = level[nodename].yellow

                                    -- if nodename == "set_provider" then
                                    -- 	print(rule.ruleid .. nodename, level[nodename].yellow, luacode, level[nodename].yellow)
                                    -- end
                                    --
                                    -- if nodename == "sim_ready" then
                                    -- 	print(rule.ruleid, " : " .. nodename,rule.debug.variables[nodename].overview["yellow"], luacode)
                                    -- end
                                end
                                if(level[nodename].green) then
                                    local luacode = substitute(rule, level[nodename].green, true)
                                    local noerror
                                    noerror, level[nodename].green = pcallchunk(luacode)
                                    rule.debug.variables[nodename].overview["green"] = level[nodename].green
                                end
                                if(level[nodename].red) then
                                    local luacode = substitute(rule, level[nodename].red, true)
                                    local noerror
                                    noerror, level[nodename].red = pcallchunk(luacode)
                                    rule.debug.variables[nodename].overview["red"] = level[nodename].red
                                end
                            end
                        end
                    end
                else
                    local report_only_this_variable = level and (level == "INFO" or level == "ERROR") and rule.debug_mode.enabled
                    if report_only_this_variable then -- debug var by editing the rule file (see comments there)
                        rule.debug.report(rule):print_var(nodename, "INFO", rule.iteration)
                    end
                end
            end
            setmetatable(dbg, { __call = function(table) return table end })
            return dbg
        end
        setmetatable(op, { __call = function(table) return table end })
        return op
    end
}

setmetatable(loadvar, loadvar_metatable)
return loadvar
