local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило открывания/закрывания шторки 'Переключение Сим' в веб-интерфейсе",
	},

	sim_id = {
		note = [[ Идентификатор активной Сим-карты: 0/1. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "sim",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]]
		}
	},


	switching = {
		note = [[ Статус переключения Sim: true / false. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "switching",
			params = {},
			--cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
            ["2_frozen"] = [[ if ($switching == "true") then return 10 else return 0 end ]],
		}
	},

	r01_do_switch = {
		note = [[ r01_do_switch  ]],
		source = {
			type = "rule",
			rulename = "01_rule",
			varname = "do_switch",
		},
	},

	r02_do_switch = {
		note = [[ r01_do_switch  ]],
		source = {
			type = "rule",
			rulename = "02_rule",
			varname = "do_switch",
		},
	},

	r03_do_switch = {
		note = [[ r01_do_switch  ]],
		source = {
			type = "rule",
			rulename = "03_rule",
			varname = "do_switch",
		},
	},

	r04_do_switch = {
		note = [[ r01_do_switch  ]],
		source = {
			type = "rule",
			rulename = "04_rule",
			varname = "do_switch",
		},
	},

	r05_do_switch = {
		note = [[ r01_do_switch  ]],
		source = {
			type = "rule",
			rulename = "05_rule",
			varname = "do_switch",
		},
	},

	r15_do_switch = {
		note = [[ r15_do_switch  ]],
		source = {
			type = "rule",
			rulename = "15_rule",
			varname = "do_switch",
		},
	},

	do_switch = {
		note = [[ Статус do_switch  ]],
		modifier = {
			["1_func"] = [[
				local DO_SWITCH = ($r01_do_switch == "true"
								or $r02_do_switch == "true"
								or $r03_do_switch == "true"
								or $r04_do_switch == "true"
								or $r05_do_switch == "true"
								or $r15_do_switch == "true")
				if DO_SWITCH then return "true" else return "false" end
			]],
			["2_frozen"] = [[ if $do_switch == "true" then return 10 else return 0 end ]]

		}
	},

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],
		modifier = {
			["1_ui-update"] = {
				param_list = {
					"switching",
                    "sim_id",
					"do_switch"
				}
			},
		}
	},
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 01_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()
	self:load("switching"):modify():debug()
	self:load("r01_do_switch"):modify():debug()
	self:load("r02_do_switch"):modify():debug()
	self:load("r03_do_switch"):modify():debug()
	self:load("r04_do_switch"):modify():debug()
	self:load("r05_do_switch"):modify():debug()
	self:load("r15_do_switch"):modify():debug()
	self:load("do_switch"):modify():debug()
	self:load("send_ui"):modify():debug()

end

---[[ Initializing. Don't edit the code below ]]---
local metatable = {
	__call = function(table, parent)
		local t = rule_init(table, rule_setting, parent)
		if not t.is_busy then
			t.is_busy = true
			t:make()
			t.is_busy = false
		end
		return t
	end
}
setmetatable(rule, metatable)
return rule
