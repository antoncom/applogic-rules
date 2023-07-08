
local util = require "luci.util"
local log = require "applogic.util.log"
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua


--[[
    Загружаем значение переменной [target_varname] из заданного правила [target_rulename]
    В правиле для переменной, в которую нужно загрузить значение другой переменной
    указываем источник например так:
    source = {
        type = "rule",
        rulename = "01_rule",
        varname = "lastreg_timer"
    },
]]
local loadvar_rule = {}
function loadvar_rule:load(varname, rule, target_rulename, target_varname)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

	local setting = rule.setting
	local varlink = rule.setting[varname] or nil

	local cache_key = ""
	local result
	local noerror = true
	local err = ""

    local RULE_EXISTS = (rule.all_rules[target_rulename] ~= nil)
    local VAR_EXISTS = RULE_EXISTS and (rule.all_rules[target_rulename].setting[target_varname] ~= nil)

    if not RULE_EXISTS then
        noerror = false
        err = string.format("There is no [%s] in the active rules list. Try 'ubus call applogic list' shell command!", target_rulename)
    elseif not VAR_EXISTS then
        noerror = false
        err = string.format("There is no [%s] variable in [%s]. Try ubus call applogic vars '{\"rule\":\"%s\"}'!", target_varname, target_rulename, target_rulename)
    else
        result = rule.all_rules[target_rulename].setting[target_varname].output or ""
    end

	if rule.debug_mode.enabled then
		if (noerror) then
			debug(varname, rule):source_rule(target_rulename, target_varname, result, noerror)
		else
			debug(varname, rule):source_rule(target_rulename, target_varname, err, noerror)
		end
	end

    return result
end

return loadvar_rule
