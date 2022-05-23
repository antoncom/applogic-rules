
local util = require "luci.util"
local log = require "openrules.util.log"
local uci = require "luci.model.uci".cursor()
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua


local loadvar = {}
loadvar.cache_ubus = {}
loadvar.cache_uci = {}
loadvar.cache_bash = {}

function loadvar:clear()
	self.cache_ubus = nil
	self.cache_ubus = {}

	self.cache_uci = nil
	self.cache_uci = {}

	self.cache_bash = nil
	self.cache_bash = {}
end

local loadvar_metatable = {
	__call = function(loadvar_table, rule, varname)

		local setting = rule.setting
		local varlink = rule.setting[varname]
		varlink.input = varlink.input or ""
		varlink.subtotal = ""
		varlink.output = ""
		local cache_key = ""

		if(rule:logic(varname) == true) then
			--[[ LOAD FROM UCI ]]
			if(varlink.source and (varlink.source.model == "uci")) then
				local config = varlink.source.config or ""
				local section = string.sub(varlink.source.section, 1) or ""
				local option = string.sub(varlink.source.option, 1) or ""

				-- Substitute variable value if uci section contains the variable name
				for name, _ in pairs(setting) do
					if(type(setting[name].output) == "string") then
						section = section:gsub("$"..name, setting[name].output)
					else
						log(string.format("openrules: Loadvar can't substitute section name to uci command from %s.output] as it's not a string value.", name))
					end
				end

				-- Substitute variable value if uci option contains the variable name
				for name, _ in pairs(setting) do
					if(type(setting[name].output) == "string") then
						option = option:gsub("$"..name, setting[name].output)
					else
						log(string.format("cpeagent:rules Loadvar can't substitute option name to uci command from %s.output] as it's not a string value.", name))
					end
				end

				-- Check cached value
				cache_key = config..section..option
				if not loadvar_table.cache_uci[cache_key] then
					local res = uci:get(config, section, option) or ""
					loadvar_table.cache_uci[cache_key] = res
				end
				varlink.input = loadvar_table.cache_uci[cache_key] or ""

			--[[ LOAD FROM UBUS ]]
			elseif (varlink.source and (varlink.source.type == "ubus")) then
				local obj = varlink.source.object or ""
				local method = varlink.source.method or ""
				local params = varlink.source.params or {}

				cache_key = md5.sumhexa(obj..method..util.serialize_json(params))

				if not loadvar_table.cache_ubus[cache_key] then
					local variable = rule.conn:call(obj, method, params)
					loadvar_table.cache_ubus[cache_key] = util.serialize_json(variable) or ""
				end
				varlink.input = loadvar_table.cache_ubus[cache_key] or ""

			--[[ LOAD FROM BASH ]]
			elseif (varlink.source and (varlink.source.type == "bash")) then
				local command = varlink.source.command or ""

				-- Substitute variable value if bash command contains the variable name
				for name, _ in pairs(setting) do
					if(type(setting[name].output) == "string") then
						command = command:gsub("$"..name, setting[name].output)
					else
						log(string.format("openrules: Loadvar can't substitute to bash command from %s.output] as it's not a string value.", name))
					end
				end

				cache_key = md5.sumhexa(command)
				if not loadvar_table.cache_bash[cache_key] then
					loadvar_table.cache_bash[cache_key] = luci.sys.exec(command) or "BASH ERROR"
				end
				varlink.input = loadvar_table.cache_bash[cache_key] or ""

			end
		end

		-- Make function chaning like this:
		-- rule:load("title"):modify()
		---------------------=========
		local mdf = {}
		function mdf:modify()

			-- Apply modifiers only if Logic func returns true
			if(rule:logic(varname) == true) then
				rule:modify(varname)
			end

			-- Make function chaning like this:
			-- rule:load("title"):modify():clear()
			------------------------------========

			local clr = {}
			function clr:clear()
				loadvar_table:clear()
			end

			local clear_metatable = {
				__call = function(clear_table)
					return clear_table
				end
			}

			setmetatable(clr, clear_metatable)
			return clr

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
