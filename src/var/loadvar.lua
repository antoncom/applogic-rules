local log = require "applogic.util.log"
local debug_cli = require "applogic.var.debug_cli"
local util = require "luci.util"


local loadvar = {}
local loadvar_metatable = {
	__call = function(loadvar_metatable, rule, varname)
		local debug
		-- Turn debug mode ON for this rule
		rule.debug_mode.enabled = (debug_cli.rule and debug_cli.rule == rule.ruleid) or rule.debug_mode.enabled
		if(debug_cli.rule and debug_cli.rule == rule.ruleid) then
			rule.debug_mode.level = "INFO"
		end
		if rule.debug_mode.enabled then
			debug = require "applogic.var.debug"
		end

		local util = require "luci.util"
		local log = require "applogic.util.log"
		local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua

		local modifier = require "applogic.modifier.main"
		local skipped = require "applogic.modifier.skip"
		local frozen = require "applogic.modifier.frozen"
		local last_mdfr_name = require "applogic.util.last_mdfr_name"

		local loadvar_ubus = require "applogic.var.loadvar_ubus"
		local loadvar_uci = require "applogic.var.loadvar_uci"
		local loadvar_bash = require "applogic.var.loadvar_bash"
		local loadvar_rule = require "applogic.var.loadvar_rule"

		local setting = rule.setting
		local varlink = rule.setting[varname]
		local report = rule.report

		-- Make variable order
		rule.variterator = rule.variterator + 1
		varlink.order = rule.variterator

		varlink.subtotal = nil
		-- If user missed input/output declaration in the rule
		varlink.input = varlink.input or ""
		--varlink.output = varlink.output or tostring(varlink.input)
		varlink.output = varlink.output or ""
		if rule.debug_mode.enabled then debug(varname, rule):order() end
		if rule.debug_mode.enabled then debug(varname, rule):note(varlink.note or "") end
		if rule.debug_mode.enabled then debug(varname, rule):input(varlink.input or "") end

		-- Check if the variable skipped
		local skipped = varlink.modifier and #util.keys(varlink.modifier) > 0 and varlink.modifier["1_skip"]
		skipped = skipped and skip(varname, rule)

		-- Check if the variable is frozen
		local frozened = varlink.frozen

		-- Check if source exists
		-- local has_source = varlink.source and varlink.source.type

		-- Load from different source
		if varlink.source then
			if (not skipped) and (not frozened) then
				if "uci" == varlink.source.type then
					varlink.subtotal = loadvar_uci:load(varname, rule)
				end

				if "ubus" == varlink.source.type then
					varlink.subtotal = loadvar_ubus:load(varname, rule)
				end

				if "bash" == varlink.source.type then
					varlink.subtotal = loadvar_bash:load(varname, rule)
				end

				if "rule" == varlink.source.type then
					varlink.subtotal = loadvar_rule:load(varname, rule, varlink.source.rulename, varlink.source.varname)
				end
			end
		end

		--[[ Make function chaining in order to use the laconic way in the rule files ]]
		-- rule:load("title"):modify()
		---------------------=========
		local mdf = {}
		function mdf:modify()
			modifier:modify(varname, rule)

			-- rule:load("title"):modify():debug()
			------------------------------========
			local dbg = {}
			function dbg:debug(...)
				local level = arg[1]
				local report_only_this_variable = level and (level == "INFO" or level == "ERROR") and rule.debug_mode.enabled
				local report_by_cli = (debug_cli.rule and debug_cli.rule == rule.ruleid)

				if report_by_cli then -- debug var by CLI like this: "applogic debug 01_rule sim_id"
					if (util.contains(debug_cli.showvar, varname)) then
					 	rule.debug.report(rule):print_var(varname, "INFO", rule.iteration)
					end
				else
					if report_only_this_variable then -- debug var by editing the rule file (see comments there)
						rule.debug.report(rule):print_var(varname, "INFO", rule.iteration)
					end
				end
			end
			setmetatable(dbg, { __call = function(table) return table end })
			return dbg
		end
		setmetatable(mdf, { __call = function(table) return table end })
		return mdf
	end
}

setmetatable(loadvar, loadvar_metatable)
return loadvar
