local log = require "applogic.util.log"

local loadvar = {}
local loadvar_metatable = {
	__call = function(loadvar_metatable, rule, varname)
		local debug
		if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

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
				local report_by_default_debug_setting = (not level) and rule.debug_mode.enabled and rule.debug_mode.type == "VAR"
				local report_only_this_variable = level and (level == "INFO" or level == "ERROR") and rule.debug_mode.enabled

				if report_by_default_debug_setting then
					rule.debug.report(rule):print_var(varname, rule.debug_mode.level, rule.iteration)
				elseif report_only_this_variable then
					rule.debug.report(rule):print_var(varname, "INFO", rule.iteration)
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
