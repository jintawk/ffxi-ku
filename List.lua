--[[A simple List data structure library - MMcGinty 2015]]

List = {}
List.__index = List

--[[
    Create a new List 
]]
function List.new()
  local li = setmetatable({}, List)
  li.first = 1
  li.last = 1
  li.count = 0
  li.items = {}
  return li
end

--[[
    Add a new item to the end of a List
    Parameters:
    item: Item to add to the List
]]
function List:push_back(item)
    if self.count ~= 0 then
        self.last = self.last + 1
    end

    self.items[self.last] = item
    self.count = self.count + 1
end

--[[
    Remove the last item from the List
]]
function List:pop_back()
    self.items[self.last] = nil
    self.last = self.last - 1
    self.count = self.count - 1

end

--[[
    Remove an item from a List
    Parameters:
    item: Item to remove
]]
function List:remove(itemid)
    local removeAt = nil

    for idx = self.first, self.first + self.count - 1 do
        if self.items[idx] == itemid then
            removeAt = idx
        end
    end

    if removeAt == nil then
        return
    end

    if removeAt ~= nil then
        self.items[removeAt] = nil

        for idx = removeAt + 1, self.first + self.count - 1 do
            self.items[idx -1] = self.items[idx]
            self.items[idx] = nil
        end
    end

    self.last = self.last - 1
    self.count = self.count - 1

end

--[[
    Remove an item from a List using index
    Parameters:
    item: Item to remove
]]
function List:remove_at(id)
    self.items[id] = nil

    for idx = id + 1, self.first + self.count - 1 do
        self.items[idx -1] = self.items[idx]
        self.items[idx] = nil
    end

    self.last = self.last - 1
    self.count = self.count - 1

end

--[[
    Check if a List contains an item
    Parameters:
    item: Item to search for
]]
function List:contains(item)
    found = false
    for idx = self.first, self.first + self.count - 1 do
        if self.items[idx] == item then
            found = true
        end
    end

    return found
end

--[[
    Clear a List of all items
]]
function List:clear(List)
    for idx = list.first, list.first + list.count - 1 do
        list.items[idx] = nil
    end

    list.first = 1
    list.last = 1
    list.count = 0
end