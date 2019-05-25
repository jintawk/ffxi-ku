require('sets')
require "Ability"
require "const"
res = require('resources')

function can_recast(action)	
 	local recasts = nil
 	local id = 0

 	if action.type == TYPE.SELF_MAGIC or action.type == TYPE.TARGET_MAGIC or action.type == TYPE.CURE_MAGIC then
 		recasts = windower.ffxi.get_spell_recasts()
 		id = action.id
	elseif action.type == TYPE.SELF_JA or action.type == TYPE.TARGET_JA or action.type == TYPE.SELF_DANCE or action.type == TYPE.TARGET_DANCE or action.type == TYPE.CURE_DANCE then
		recasts = windower.ffxi.get_ability_recasts()
 		id = action.recast_id
	else
		log('Error in can_recast: unknown type -> ' .. action.type, action)
	end 	 

	if recasts[id] == 0 then
		log_d('Recast == 0 (true)', action)
		return true
	else
		log_d('Recast > 0 (false)', action)
		return false
	end
end

function enough_mp(action)
	-- JA	
	if action.type == TYPE.SELF_JA or action.type == TYPE.TARGET_JA then
		log_d('Enough Mp TRUE as it is a JA')
		return true
	end

	-- DANCE
	if action.type == TYPE.SELF_DANCE or action.type == TYPE.TARGET_DANCE or action.type == TYPE.CURE_DANCE then
		local tpRequired = res.job_abilities[action.id].tp_cost
		local playerTp = windower.ffxi.get_player().vitals.tp

		if playerTp >= tpRequired then
			log_d('Sufficient TP (' .. playerTp .. '/' .. tpRequired .. ')', action)
			return true
		else
			log('Insufficient TP (' .. playerTp .. '/' .. tpRequired .. ')', action)
			return false
		end
	end

	-- MAGIC
	local mpRequired = res.spells[action.id].mp_cost
	local playerMp = windower.ffxi.get_player().vitals.mp

	if playerMp >= mpRequired then
		log_d('Sufficient MP (' .. playerMp .. '/' .. mpRequired .. ')', action)
		return true
	else
		log('Insufficient MP (' .. playerMp .. '/' .. mpRequired .. ')', action)
		return false
	end
end

function is_buff_on(action)
	for i,v in pairs(windower.ffxi.get_player()['buffs']) do 
 		if v == action.buff_id then
 			log_d('Found buff to be ON', action)
 			return true
		end
	end	

	log_d('Found buff to be OFF', action)
	return false
end

function should_recast(action, engaged)
	local should = false

	if action.type == TYPE.CURE_DANCE or action.type == TYPE.CURE_MAGIC then
		local playerHpp = windower.ffxi.get_player().vitals.hpp

		if playerHpp > action.hpPerc then
			log_d('Hp not low enough for cure', action)
			return false
		end
	end

	if action.when == nil and engaged then
		should = true
	elseif action.when == WHEN.ALL then
		should = true
	elseif action.when == WHEN.IN and engaged then 
		should = true
	elseif action.when == WHEN.OUT and not engaged then
		should = true
	end

	if should then
		log_d('Should recast TRUE', action)
	else
		log_d('Should recast FALSE', action)
	end

	return should
end

function log(msg, action)
	if action ~= nil then
		msg = '[' .. action.name .. '] ' .. msg
	end

	windower.add_to_chat(207, "KU -> " .. msg)
end

function log_d(msg, action)
	if debug then
		if action ~= nil then
			msg = '[' .. action.name .. '] ' .. msg
		end

		windower.add_to_chat(207, "KU [dbg] -> " .. msg)
	end
end

function log_invalid_params(msg)
	log('Invalid params. Run "//ku help" for examples')
end

function get_help_string()
	return [[Command Examples

	-Magic cast on self
	Params -> //ku add selfma [spell] [spell_id] [buff_id] [when]
	Example -> //ku add selfma Cocoon 547 93 in

	-JA used on self-
	Params -> //ku add selfja [ja] [ability_id] [recast_id] [when]
	Example -> //ku add selfja Drain_Samba 184 368 216 in

	-Magic used on target
	Params -> //ku add targma [spell] [spell_id]
	Example -> //ku add targma Jet_Stream 569

	-JA used on target
	Params -> //ku add selfja [ja] [ability_id] [recast_id]
	Example -> //ku add targja Box_Step 202 220

	-Curing magic used on self
	Params -> //ku add curema [spell] [when] [hp%]
	Example -> //ku add curema Cure_IV all 75

	-Remove from action list
	Params -> //ku remove [id]
	Example -> //ku remove 3	

	-Restrict KU to a single zone
	Params -> //ku zone [id]
	Example (Yorcia) -> //ku zone 263

	Notes:
	Valid [when] options are 'all' 'out' and 'in' combat
	Multi-word abilities MUST have underscores, e.g -> Drain_Samba
	[spell_id] found at windower github -> Windower/Resources/spells
	[ability_id] found at windower github -> Windower/Resources/job_abilities
	[buff_id] found at windower github -> Windower/Resources/buffs
	[recast_id] found at windower github -> Windower/Resources/ability_recasts
	]]
end