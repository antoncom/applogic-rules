local log = require "applogic.util.log"
local debug_cli = require "applogic.var.debug_cli"
local util = require "luci.util"
local substitute = require "applogic.util.substitute"
local pcallchunk = require "applogic.util.pcallchunk"




local loadvar = {}
local loadvar_metatable = {
	__call = function(loadvar_metatable, rule, varname)
		local debug
		-- Turn debug mode ON for this rule
		--rule.debug_mode.enabled = (debug_cli.rule and debug_cli.rule == rule.ruleid) or rule.debug_mode.enabled
		if(debug_cli.rule and debug_cli.rule == rule.ruleid) then
			rule.debug_mode.level = "INFO"
		end
		if rule.debug_mode.enabled then
			debug = require "applogic.var.debug"
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
		if (not rule["default"][varname]) then
			rule["default"][varname] = util.clone(rule.setting[varname])
			if rule["default"][varname].source then rule["default"][varname].source = nil end
			if rule["default"][varname].note then rule["default"][varname].note = nil end
			if rule["default"][varname].modifier then rule["default"][varname].modifier = nil end
		end

		-- Also we keep there "overview" debug info if the variable was chosen for this
		-- See below in the debug place

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
		local loadvar_subscribed = require "applogic.var.loadvar_subscribed"

		local setting = rule.setting
		local varlink = rule.setting[varname]
		local report = rule.report

		-- Make variable order
		rule.variterator = rule.variterator + 1
		varlink.order = rule.variterator

		-- TODO
		-- Убедиться что второй вариант рабтотает верно.
		--1) varlink.subtotal = nil
		--2)
		varlink.subtotal = varlink.subtotal or nil

		-- end of TODO

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
			--if (not skipped) and (not frozened) then
			if not (skipped or frozened) then
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

				if "subscribe" == varlink.source.type then
					loadvar_subscribed:load(varname, rule)
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
				local report_by_cli = (debug_cli.rule and debug_cli.rule == rule.ruleid)
				local overview_by_cli = (debug_cli.rule and debug_cli.rule == "overview")

				if report_by_cli then -- debug var by CLI like this: "applogic debug 01_rule sim_id"
					if (util.contains(debug_cli.showvar, varname)) then
					 	rule.debug.report(rule):print_var(varname, "INFO", rule.iteration)
					end
				elseif overview_by_cli then
					if (type(level) == "table") then
						local overview_vars_for_this_rule = util.keys(level)
						rule["default"]["overviewed_vars"] = util.clone(overview_vars_for_this_rule)
						if (util.contains(overview_vars_for_this_rule, varname)) then
							if(type(level[varname]) == "string") then
								rule.debug.variables[varname].overview = level[varname]
							elseif(type(level[varname]) == "table") then
								-- realize colorizing policy of overview report according to subsituted value
								rule.debug.variables[varname].overview = {}
								if(level[varname].yellow) then
									local luacode = substitute(varname, rule, level[varname].yellow, false, true)
									local noerror
									noerror, level[varname].yellow = pcallchunk(luacode)
									rule.debug.variables[varname].overview["yellow"] = level[varname].yellow

									-- if varname == "set_provider" then
									-- 	print(rule.ruleid .. varname, level[varname].yellow, luacode, level[varname].yellow)
									-- end
									--
									-- if varname == "sim_ready" then
									-- 	print(rule.ruleid, " : " .. varname,rule.debug.variables[varname].overview["yellow"], luacode)
									-- end
								end
								if(level[varname].green) then
									local luacode = substitute(varname, rule, level[varname].green, false, true)
									local noerror
									noerror, level[varname].green = pcallchunk(luacode)
									rule.debug.variables[varname].overview["green"] = level[varname].green
								end
								if(level[varname].red) then
									local luacode = substitute(varname, rule, level[varname].red, false, true)
									local noerror
									noerror, level[varname].red = pcallchunk(luacode)
									rule.debug.variables[varname].overview["red"] = level[varname].red
								end
							end
						end
					end
				else
					local report_only_this_variable = level and (level == "INFO" or level == "ERROR") and rule.debug_mode.enabled
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
