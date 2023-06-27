local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения если нет Cим-карты в слоте",
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

	uci_timeout_sim_absent = {
		note = [[ Таймаут отсутствия Сим карты. Источник: /etc/config/tsmodem  ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmodem",
				section = "default",
				option = "timeout_sim_absent",
			}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	sim_ready = {
		note = [[ Сим-карта в слоте? "true" / "false" ]],
		--input = "true",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "cpin",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_frozen"] = [[ if $sim_ready == "" then return 6 else return 0 end ]] -- debounce AT+CPIN? when switching
		}
	},

	ready_time = {
		note = [[ Время когда Сим-карта была замечена в слоте или момент переключения слотов ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "cpin",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]]
		}
	},

	timer = {
		note = [[ Отсчёт секунд при отсутствии Сим-карты в слоте. ]],
		input = "0", -- Set default value if you need "reset" variable before skipping
		modifier = {
			["1_skip"] = [[ return ($sim_ready == "true") ]],
			["2_func"] = [[
				local TIMER = tonumber($ready_time) and (os.time() - $ready_time) or false
				if TIMER then return TIMER else return "0" end
			]],
		}
	},

    reset_modem = {
		note = [[ Подать сигнал сброса на модем через каждые 10 сек. ]],
        source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "send_at",
			params = { command = "AT+CRESET"},
		},
		modifier = {
			["1_skip"] = [[ return ($sim_ready == "true") ]],
			["2_frozen"] = [[ return 20 ]]
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

	do_switch = {
		note = [[ Активирует и возвращает трезультат переключения Сим-карты  ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = { rule = "01_rule"},
		},
		modifier = {
			["1_skip"] = [[
				local READY = 	( $switching == "" or $switching == "false" )
				local TIMEOUT = tonumber($timer) and ( $timer > $uci_timeout_sim_absent )
				return ( not (READY and TIMEOUT) )
			]],
			["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_frozen"] = [[ if $do_switch == "true" then return 10 else return 0 end ]]
		}
	},

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],
		modifier = {
			["1_ui-update"] = {
				param_list = {
					"sim_id",
					"timer",
					"sim_ready",
					"uci_timeout_sim_absent",
					"do_switch",
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
	self:load("uci_timeout_sim_absent"):modify():debug()
	self:load("sim_ready"):modify():debug()
	self:load("ready_time"):modify():debug()

	self:load("reset_modem"):modify():debug()

    self:load("timer"):modify():debug()
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
