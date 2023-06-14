local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Cим-карты при отсутствии регистрации в сети",
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

	uci_section = {
		note = [[ Идентификатор секции вида "sim_0" или "sim_1". Источник: /etc/config/tsmodem ]],
		modifier = {
			["1_func"] = [[ if ($sim_id == 0 or $sim_id == 1) then return ("sim_" .. $sim_id) else return "sim_0" end ]],
		}
	},

	uci_timeout_reg = {
		note = [[ Таймаут отсутствия регистрации в сети. Источник: /etc/config/tsmodem  ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmodem",
				section = "$uci_section",
				option = "timeout_reg",
			}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_func"] = [[ if ( $uci_timeout_reg == "" or tonumber($uci_timeout_reg) == nil) then return "99" else return $uci_timeout_reg end ]],
		}
	},

	-- sim_ready = {
	-- 	note = [[ Сим-карта в слоте? "true" / "false" ]],
	-- 	input = "true",
	-- 	source = {
	-- 		type = "ubus",
	-- 		object = "tsmodem.driver",
	-- 		method = "cpin",
	-- 		params = {},
	-- 	},
	-- 	modifier = {
	-- 		["1_bash"] = [[ jsonfilter -e $.value ]],
	-- 	}
	-- },

	network_registration = {
		note = [[ Статус регистрации Сим-карты в сети 0..7. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "reg",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			-- ["2_func"] = [[
			-- 	if ($sim_ready == "true") then return $network_registration
			-- 	elseif ($sim_ready == "false") then return "-1"
			-- 	else return $network_registration end
			-- ]]
		}
	},

	changed_reg_time = {
		note = [[ Время последней успешной регистрации в сети или "", если неизвестно. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "reg",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]]
		}
	},

	lastreg_timer = {
		note = [[ Отсчёт секунд при потере регистрации Сим-карты в сети. ]],
		input = "0", -- Set default value if you need "reset" variable before skipping
		modifier = {
			["1_skip"] = [[ return ($network_registration == 1 or $network_registration == 7) ]],
			["2_func"] = [[
				local TIMER = tonumber($changed_reg_time) and (os.time() - $changed_reg_time) or false
				if TIMER then return TIMER else return "0" end
			]],
		}
	},

	switching = {
		note = [[ Статус переключения Sim: true / false. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "switching",
			params = {},
			cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	do_switch = {
		note = [[ Активирует и возвращает трезультат переключения Сим-карты  ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = {},
		},
		modifier = {
			["1_skip"] = [[
				local READY = 	( $switching == "" or $switching == "false" )
				local TIMEOUT = tonumber($lastreg_timer) and ( $lastreg_timer > $uci_timeout_reg )
				--local SIM_ABSENT = ($sim_ready == "false")
				--return ( not ((READY and TIMEOUT) or SIM_ABSENT) )
				return ( not (READY and TIMEOUT) )
			]],
			["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_frozen"] = [[ if $do_switch == "true" then return 10 else return 0 end ]]
			-- ["3_ui-update"] = {
			-- 	param_list = { "do_switch", "sim_id" }
			-- },
			-- ["4_init"] = {
			-- 	vars = {"lastreg_timer", "sim_ready"}
			-- },
		}
	},

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],
		modifier = {
			["1_ui-update"] = {
				param_list = {
					"sim_id",
					"lastreg_timer",
					"event_switch_state",
					"changed_reg_time",
					"network_registration",
					"lastreg_timer"
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
	self:load("uci_section"):modify():debug()
	self:load("uci_timeout_reg"):modify():debug()

	-- self:load("sim_ready"):modify():debug()
	self:load("network_registration"):modify():debug()
	self:load("changed_reg_time"):modify():debug()
	self:load("lastreg_timer"):modify():debug()
	self:load("switching"):modify():debug()
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
