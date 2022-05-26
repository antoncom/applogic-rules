
local util = require "luci.util"
local log = require "applogic.util.log"
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local logic = require "modifier.logic"
local modifier = require "modifier.all"

local loadvar_ubus = require "applogic.var.loadvar_ubus"
local loadvar_uci = require "applogic.var.loadvar_uci"
local loadvar_bash = require "applogic.var.loadvar_bash"

local loadvar = {}
local loadvar_metatable = {
	__call = function(loadvar_table, rule, varname)
		local debug = require "applogic.var.debug".init(rule)
		local setting = rule.setting
		local varlink = rule.setting[varname]
		local report = rule.report

		-- If user missed input/output declaration in the rule
		varlink.input = varlink.input or ""
		varlink.output = varlink.output or ""

		local initial = string.format("%s", varlink.input or "")
		--debug(varname):input(initial:gsub("\t", " "))

		if varlink.source and varlink.source.type and varlink.source.type == "uci" then
			loadvar_uci:load(varname, rule)
		end
		if varlink.source ~= nil and varlink.source.type ~= nil and varlink.source.type == "ubus" then
			loadvar_ubus:load(varname, rule)
		end
		if varlink.source and varlink.source.type and varlink.source.type == "bash" then
			loadvar_bash:load(varname, rule)
		end

		-- Make function chaning like this:
		-- rule:load("title"):modify()
		---------------------=========
		local mdf = {}
		function mdf:modify()
			if not logic:skip(varname, rule) then
				modifier:modify(varname, setting, rule)
			end

			local dbg = {}
			function dbg:debug(level)
				if level then
					rule.report:print(varname, level, rule.iteration)
				end
			end

			local dbg_metatable = {
				__call = function(clear_table)
					return clear_table
				end
			}
			setmetatable(dbg, dbg_metatable)
			return dbg
		end

		local modify_metatable = {
			__call = function(modify_table)
				return modify_table
			end
		}
		setmetatable(mdf, modify_metatable)
		return mdf
	end
}

setmetatable(loadvar, loadvar_metatable)
return loadvar
