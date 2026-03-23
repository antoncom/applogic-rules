local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило для управления роутером по СМС.",
	},

    max_text_size = {
        note = [[ Максимальный размер текста для отправки по смс, иначе отправка через email ]],
        default = 201, -- 3 смс кусочка по 67 символов
    },

    received_sms = {
		note = [[ Подписка на чтение новой смс ]],
		default = "",

		{
			["subscribe"] = {
				ubus = "tsmodem.sms",
				evname = "NEW-SMS-RECEIVED",
				match = { status = "ok"},
			}
		},
		{
			["func"] = function (nodes)
                local lua_table = luci.jsonc.parse(nodes.received_sms) or {}
				return lua_table or ""
			end,
		}
	},

    call_tsmsmscomm_run = {
        note = [[ Вызывает метод выполнения команды полученной по смс ]],

        {
            ["skip"] = function (nodes)
                return #nodes.received_sms <= 2
            end
        },
        {
            ["load-ubus"] = function (nodes)
                local sms_data_table = luci.jsonc.parse(nodes.received_sms)

                return ({
                    object = "tsmsmscomm",
                    method = "run",
                    params = {
                        phone = sms_data_table.sender,
                        message = sms_data_table.message,
                    },
                })
            end
        }
    },

    tsmsmscomm_run_result = {
        note = [[ Подписка на получение результата выполненной команды ]],
        default = "",

        {
            ["subscribe"] = {
                ubus = "tsmsmscomm",
                evname = "result",
                match = {},
            },
        },
        {
            ["func"] = function (nodes)
                -- print('tsmsmscomm_run_result type: ', type(nodes.tsmsmscomm_run_result))
                -- print('tsmsmscomm_run_result: ', nodes.tsmsmscomm_run_result)

                -- local lua_table = luci.jsonc.parse(nodes.tsmsmscomm_run_result)

                if type(nodes.tsmsmscomm_run_result) == "table" then
                    local file = io.open(nodes.tsmsmscomm_run_result.tmp_file, "r")
                    if file ~= nil then
                        nodes.tsmsmscomm_run_result.result = file:read("*a")
                        file:close()
                    end
                end

                return nodes.tsmsmscomm_run_result or ""
            end
        },
    },

    sms_answer = {
        title = [[ Отправляет результат по смс, если текст вмещается в max_text_size ]],

        {
            ["skip"] = function (nodes)
                if nodes.tsmsmscomm_run_result == nil or
                    type(nodes.tsmsmscomm_run_result) ~= "table" or
                    nodes.tsmsmscomm_run_result.run == nil or
                    nodes.tsmsmscomm_run_result.run == false
                then
                    return true
                end

                return (nodes.tsmsmscomm_run_result.result == nil or #nodes.tsmsmscomm_run_result.result == 0)
                    or #nodes.tsmsmscomm_run_result.result > tonumber(nodes.max_text_size)
            end
        },
        {
            ["send-sms"] = function (nodes)
                return ({
                    phone = nodes.tsmsmscomm_run_result.trusted_phone,
                    text = nodes.tsmsmscomm_run_result.result,
                })
            end
        },
        -- { -- send sms (load-ubus instead of send-sms)
        --     ["load-ubus"] = function (nodes)
        --         return ({
        --             object = "tsmodem.sms",
        --             method = "send_sms",
        --             params = {
        --                 phone = nodes.tsmsmscomm_run_result.trusted_phone,
        --                 text = nodes.tsmsmscomm_run_result.result,
        --             }
        --         })
        --     end
        -- },
    },





    -- send_result_via_email = {
    --     title = [[ Отправляет результат по email, если текст более чем max_text_size ]],

    --     {
    --         ["skip"] = function (nodes)
    --             if nodes.run_cmd == nil or #nodes.run_cmd == 0 then return true end

    --             local run_cmd = luci.jsonc.parse(nodes.run_cmd)
    --             if run_cmd.status == false then
    --                 return true
    --             end

    --             return (run_cmd.result == nil or #run_cmd.result == 0) or #run_cmd.result <= tonumber(nodes.max_text_size)
    --         end
    --     },
    --     {
    --         ["func"] = function (nodes)
    --             local run_cmd = luci.jsonc.parse(nodes.run_cmd)
    --             return run_cmd.result
    --         end
    --     },
    --     {
    --         ["send-email"] = {
    --             to = "$trusted_email",
    --             subj = "Результат выполнения команды",
    --             body = "Результат выполнения команды",
    --             attach = "/tmp/sms_command_output.txt",
    --         }
    --     }
    -- },

    -- journal = {
	-- 	{
	-- 		["skip"] = function (nodes)
    --             if nodes.run_cmd == nil or #nodes.run_cmd == 0 then return true end
    --             local run_cmd = luci.jsonc.parse(nodes.run_cmd)
    --             return run_cmd.status == false
	-- 		end
	-- 	},
	-- 	{
	-- 		["func"] = function (nodes)
	-- 			local received_sms = luci.jsonc.parse(nodes.received_sms)
    --             local run_cmd = luci.jsonc.parse(nodes.run_cmd)
	-- 			return({
	-- 				datetime = received_sms.date,
	-- 				name = "Получена SMS-команда",
	-- 				source = received_sms.sender,
	-- 				command = received_sms.message,
	-- 				response = run_cmd.result,
	-- 			})
	-- 		end
	-- 	},
	-- 	{
	-- 		["store-db"] = {
	-- 			param_list = { "journal" }
	-- 		},
	-- 	}
	-- },
}

function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	local overview = {}

    self:follow("max_text_size"):debug()
    self:follow("received_sms"):debug()

    self:follow("call_tsmsmscomm_run"):debug()
    self:follow("tsmsmscomm_run_result"):debug()
    self:follow("sms_answer"):debug()



    -- self:follow("new_sms_phone"):debug()
    -- self:follow("new_sms_message"):debug()

    -- self:follow("trusted_phone"):debug()
    -- self:follow("allowed_command"):debug()
    -- self:follow("trusted_email"):debug()

    -- self:follow("run_cmd"):debug()



    -- self:follow("send_result_via_sms"):debug()
    -- self:follow("send_result_via_email"):debug()

    -- self:follow("journal"):debug()
end

local metatable = {
    __call = function(table, parent)
        local rule_init_table = rule_init(table, rule_setting, parent)
        rule_init_table:make()
        return rule_init_table
    end
}
setmetatable(rule, metatable)
return rule
