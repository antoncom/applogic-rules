local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"


local rule = {}
local rule_setting = {

	title = {
		input = "Переключение CPE Agent на резервный хост.",
	},

	cpe_status = {
		note = [[ Статус CPE Agent. Если включен - возвращает "OK". ]],
		source = {
			type = "ubus",
			object = "cpeagent",
			method = "status"
		},
		modifier = {
			["1_skip"] = [[
				local NOT_switching_now = ($swith_cpe ~= "switching")
				return (not NOT_switching_now)
			]],
			["2_bash"] = [[ jsonfilter -e '$.state' 2>/dev/null ]],
			["3_func"] = [[ if string.len($cpe_status) > 0 then return "OK" else return "" end ]],
		}
	},

	cpe_host = {
		note = [[ Адрес активного хоста брокера CPE (ubus-запрос с интервалом 2 сек.) ]],
		source = {
			type = "ubus",
			object = "cpeagent",
			method = "status"
		},
		modifier = {
			["1_skip"] = [[
				local cpe_status_OK = ($cpe_status ~= "")
				local NOT_switching_now = ($swith_cpe ~= "switching")
				return not (cpe_status_OK and NOT_switching_now)
			]],
			["2_bash"] = [[ jsonfilter -e '$.broker.host' 2>/dev/null ]],
		}
	},

	cpe_pinged = {
		note = [[ Пингутет текущий хост CPE с интервалом 5 сек. и возвращает "1" или "0". ]],
		modifier = {
			["1_skip"] = [[
				local cpe_status_OK = ($cpe_status ~= "")
				local NOT_switching_now = ($swith_cpe ~= "switching")
				return not (cpe_status_OK and NOT_switching_now)
			]],
			["2_bash"] = "/usr/lib/lua/applogic/sh/pingcheck.sh --host $cpe_host",
			["3_func"] = [[ return string.sub($cpe_pinged,1,1) ]],
			["4_frozen"] = "return(5)"
		}
	},

	last_alive_time = {
			note = [[ Время когда PING был OK (если CPE выключен, тоже считаем что хост "жив" ]],
			input = os.time(),
			modifier = {
				["1_skip"] = [[
					local cpe_pinged_OK = ('$cpe_pinged' == '1')
					local cpe_status_FAIL = ($cpe_status ~= "OK")
					return not (cpe_pinged_OK or cpe_status_FAIL)
				]],
				["2_func"] = [[ return os.time() ]],
				["3_save"] = [[ return $last_alive_time ]]
			}
	},

	all_hosts = {
		note = [[ Список всех хостов CPE Agent-а ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "wimark",
				type = "broker"
			}
		},
		modifier = {
			["1_skip"] = [[
				local cpe_status_OK = ($cpe_status ~= "")
				return (not cpe_status_OK)
			]],
			["2_bash"] = [[ jsonfilter -e '$.values.*.host' | awk -v RS=  '{$1=$1}1' | tr " " ";" ]],
		}
	},

	alived_hosts = {
		note = [[ Пингутет все хосты, возвращает только действующие (раз в 5 сек.) ]],
		modifier = {
			["1_skip"] = [[
				local cpe_status_OK = ($cpe_status ~= "")
				local all_hosts_OK = ($all_hosts ~= "")
				local NOT_switching_now = ($swith_cpe ~= "switching")
				return not (cpe_status_OK and all_hosts_OK and NOT_switching_now)
			]],
			["2_bash"] = "/usr/lib/lua/applogic/sh/pingcheck.sh --host-list $all_hosts | awk /^1/ | sed s/1[[:space:]]// | awk -v RS=  '{$1=$1}1' | tr ' ' ';'",
			["3_frozen"] = "return(5)"
		}
	},

	timer = {
		note = [[ Отсчитывает время, начиная от $last_alive_time ]],
		input = "0",
		modifier = {
			["1_skip"] = [[
				local NOT_switching_now = ($swith_cpe ~= "switching")
				local last_alive_time_OK = (type($last_alive_time) == "number")
				return not (NOT_switching_now and last_alive_time_OK)
			]],
			["2_func"] = [[ return (os.time() - $last_alive_time) ]],
		}
	},

	swith_cpe = {
		note = [[ Делаем "ubus call cpeagent reset" если за 20с текущий хост FAIL и резервный список не пуст. ]],
		source = {
			type = "ubus",
			object = "cpeagent",
			method = "reset"
		},
		modifier = {
			["1_skip"] = [[
				local cpe_status_OK = ($cpe_status ~= '')
				local cpe_pinged_FAIL = ('$cpe_pinged' ~= '1')
				local alived_hosts_OK = ($alived_hosts ~= '')
				local exceeded = ($timer > 20)
				return not (cpe_status_OK and cpe_pinged_FAIL and alived_hosts_OK and exceeded)
			]],
			["2_func"] = [[ return "switching" ]],
			["3_frozen"] = "return({10,string.format('done at: %s', os.date())})"
		}
	}
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug mode: RULE or VAR
-- Use :debug("INFO") - to debug single variable in the rule (ERROR also is possible)
function rule:make()
	local ONLY = rule.debug_mode.level
	debug_mode.type = "RULE"
	debug_mode.level = "INFO"
	rule.debug_mode = debug_mode

	self:load("title"):modify():debug()	-- Use debug(ONLY) to check the var only

	self:load("cpe_status"):modify():debug()
	self:load("cpe_host"):modify():debug()
	self:load("cpe_pinged"):modify():debug()
	self:load("last_alive_time"):modify():debug()

	self:load("all_hosts"):modify():debug()
	self:load("alived_hosts"):modify():debug()

	self:load("timer"):modify():debug()
	self:load("swith_cpe"):modify():debug()
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

-- ubus call uci set '{"config":"wimark","type":"broker","section":"cfg0b2e8a","values":{"host":"192.168.1.22"}}'
