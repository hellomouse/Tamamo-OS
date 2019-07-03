-- a doubly linked list
-- will create keys _llprev and _llnext on list objects
-- assumes the same object does not somehow get put in the list twice
local LinkedList = {}
LinkedList.__index = LinkedList

function LinkedList:create()
    local obj = setmetatable({
        first = nil,
        last = nil,
        length = 0
    }, LinkedList)
    return obj
end

function LinkedList:prepend(obj)
    local oldFirst = self.first
    self.first = obj
    obj._llprev = nil
    if oldFirst then
        obj._llnext = oldFirst
        oldFirst._llprev = obj
    else
        obj._llnext = nil
        self.last = obj
    end
    self.length = self.length + 1
end

function LinkedList:append(obj)
    local oldLast = self.last
    self.last = obj
    obj._llnext = nil
    if oldLast then
        obj._llprev = oldLast
        oldLast._llnext = obj
    else
        obj._llprev = nil
        self.first = obj
    end
    self.length = self.length + 1
end

function LinkedList:insertAfter(obj1, obj2)
    if not obj1 then return self:prepend(obj2) end
    local oldNext = obj1._llnext
    obj1._llnext = obj2
    obj2._llprev = obj1
    obj2._llnext = oldNext
    if oldNext then oldNext._llprev = obj2
    else self.last = obj2 end
    self.length = self.length + 1
end

function LinkedList:insertBefore(obj1, obj2)
    if not obj1 then return self:append(obj2) end
    local oldPrev = obj1._llprev
    obj1._llprev = obj2
    obj2._llnext = obj1
    obj2._llprev = oldPrev
    if oldPrev then oldPrev._llnext = obj2
    else self.first = obj2 end
    self.length = self.length + 1
end

function LinkedList:remove(obj)
    local oldPrev = obj._llprev
    local oldNext = obj._llnext
    if oldPrev then oldPrev._llnext = oldNext
    else self.first = oldNext end
    if oldNext then oldNext._llprev = oldPrev
    else self.last = oldPrev end
    obj._llprev = nil
    obj._llnext = nil
    self.length = self.length - 1
end

return LinkedList
