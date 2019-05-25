require "List"
require "const"
config = require('config')
texts = require('texts')

defaults = {}
defaults.pos = {}
defaults.pos.x = 300
defaults.pos.y = 475
defaults.text = {}
defaults.text.font = 'Arial'
defaults.text.size = 8
defaults.flags = {}
defaults.flags.bold = true
defaults.flags.draggable = true
defaults.bg = {}
defaults.bg.alpha = 128

settings = config.load(defaults)

listGUI = texts.new(settings)
settings = config.load()

function update_gui(list, zone)
	if list.count > 0 then
		local guiStr = "KU List:"

		if zone ~= nil then
			guiStr = guiStr .. " [" .. zone .. "]"
		end

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