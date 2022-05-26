
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
	local config = varlink.source.config
	local section = varlink.source.section
	local option = varlink.source.option

	noerror = config and section and option

	if noerror then
		-- Check cached value
		cache_key = config..section..option
		if not rule.cache_uci[cache_key] then
			-- Cache result only if no error occures
			if noerror then
				rule.cache_uci[cache_key] = uci:get(config, section, option)
			end
		end
	end
	result = noerror and rule.cache_uci[cache_key] or ""
	debug(varname):source_uci((config or ""), (section or ""), (option or ""), rule.cache_uci[cache_key] or "", noerror)


	-- Loaded result is stored as the variable "input" param
	varlink.subtotal = result
	debug(varname):input(string.format("%s", result))

end

return loadvar_uci
