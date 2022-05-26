
local util = require "luci.util"
local log = require "applogic.util.log"
local uci = require "luci.model.uci".cursor()
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local nixio = require "nixio"

local loadvar_uci = {}

function loadvar_uci:load(varname, rule)
	local debug = require "applogic.var.debug".init(rule)
	local setting = rule.setting
	local varlink = rule.setting[varname]
	local cache_key = ""
	local result = ""
	local noerror = true


	--[[ LOAD FROM UCI ]]
	local config = varlink.source.config or ""
	local section = string.sub(varlink.source.section, 1) or ""
	local option = string.sub(varlink.source.option, 1) or ""

	-- Substitute variable value if uci section contains the variable name
	for name, _ in pairs(setting) do
		if(type(setting[name].output) == "string") then
			section = section:gsub("$"..name, setting[name].output)
		else
			print(string.format("applogic: Loadvar can't substitute section name to uci command from [%s.output] as it's not a string value.", name))
		end
	end

	-- Substitute variable value if uci option contains the variable name
	for name, _ in pairs(setting) do
		if(type(setting[name].output) == "string") then
			option = option:gsub("$"..name, setting[name].output)
		else
			print(string.format("cpeagent:rules Loadvar can't substitute option name to uci command from [%s.output] as it's not a string value.", name))
		end
	end

	-- Check cached value
	cache_key = config..section..option
	if not loadvar_uci.cache[cache_key] then
		noerror = uci:load(config)
		-- Cache result only if no error occures
		if noerror then
			loadvar_uci.cache[cache_key] = uci:get(config, section, option)
		end
	end
	result = noerror and loadvar_uci.cache[cache_key] or ""
	debug(varname):source_uci(config, section, option, rule.cache_bash[cache_key] or "", noerror)


	-- Loaded result is stored as the variable "input" param
	varlink.input = result
	debug(varname):input(result)

end

return loadvar_uci
