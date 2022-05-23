
require "os"
require "ubus"
local sys  = require "luci.sys"
local uloop = require "uloop"
local util = require "luci.util"
local log = require "openrules.util.log"
local flist = require "openrules.util.filelist"
local uci = require "luci.model.uci".cursor()
local bit = require "bit"

local F = require "posix.fcntl"
local U = require "posix.unistd"

local config = "wimark"


local rules = {}
rules.ubus_object = {}
rules.conn = 0

local rules_setting = {
	title = "Группа правил CPE Agent",
	rules_list = {
		target = {},
	},
	tick_size_default = 1000
}

function rules:make_ubus()
	self.conn = ubus.connect()
	if not self.conn then
		error("rules:make_ubus() - Failed to connect to ubus")
	end

	local ubus_object = {
		["cpeagent.rules"] = {
			list = {
				function(req, msg)
					local rlist = {}
					for rule_file, rule_obj in util.kspairs(self.setting.rules_list.target) do
						rlist[rule_file] = rule_obj.setting.title.output
					end
					self.conn:reply(req, { rule_list = rlist })
				end, {id = ubus.INT32, msg = ubus.STRING }
			},

			vars = {
				function(req, msg)
					local vlist = {}
					local rules = self.setting.rules_list.target
					local rule_name = msg["rule"]
					if not rule_name then
						self.conn:reply(req, { ["error"] = "Rule name was not found. Try 'list' to see all names."})
						return
					end

					if rules[rule_name] and rules[rule_name].setting then
						for varname, varparams in pairs(rules[rule_name].setting) do
							vlist[varname] = (type(varparams["output"]) == "table") and util.serialize_json(varparams["output"]) or varparams["output"]
						end
					else
						self.conn:reply(req, { ["error"] = string.format("Rule '%s' was not found.", tostring(rule_name)) })
					end

					self.conn:reply(req, { variables = vlist })

				end, {id = ubus.INT32, msg = ubus.STRING }
			},
		},
	}
	self.conn:add( ubus_object )
	self.ubus_object = ubus_object

end

function rules:make()
	local rules_path = "/usr/lib/lua/openrules/rule"
	local id, rules = '', self.setting.rules_list.target

	local files = flist({path = rules_path, grep = ".lua"})
	for i=1, #files do
		id = util.split(files[i], '.lua')[1]
		rules[id] = require("openrules.rule." .. id)
	end

	util.dumptable(rules)
end


function rules:run_all(varlink)
	local rules = self.setting.rules_list.target
	local state = ''

	for name, rule in util.kspairs(rules) do
		-- Initiate rule with link to the present (parent) module
		-- Then the rule can send notification on the ubus object of parent module
		state = rule(self)
	end
end

local metatable = {
	__call = function(table)
		table.setting = rules_setting
		local tick = table.setting.tick_size_default

		table:make_ubus()
		table:make()

		-- looping
		uloop.init()

		local timer
		function t()
			table:run_all()
			timer:set(tick)
		end
		timer = uloop.timer(t)
		timer:set(tick)

		uloop.run()

		table.conn:close()
		return table
	end
}
setmetatable(rules, metatable)
rules()
