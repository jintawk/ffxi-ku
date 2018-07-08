require "List"
require "const"
config = require('config')
texts = require('texts')

listGUI = texts.new(settings)
settings = config.load()

function update_gui(list)
	if list.count > 0 then
		local guiStr = "KU List:"

		for i = list.first, list.first + list.count - 1 do
			local item = list.items[i]
			if item ~= nil then
				if item.when == nil then
					guiStr = guiStr .. "\n" .. i .. ": " .. item.name .. ' (' .. item.type .. ')'
				else
					guiStr = guiStr .. "\n" .. i .. ": " .. item.name .. ' (' .. item.type .. '-' .. item.when .. ')'
				end
			end
		end

		listGUI:text(guiStr)
		listGUI:visible(true)
	end
end