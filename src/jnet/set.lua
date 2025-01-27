local check = require("jnet.check")
local net = require("jnet.net")

local set_i = {}
local set_m = { __index = set_i, jnet_type__ = "jnet.set" }

local function replace(old_node, new_node)
	local up = old_node.up
	if up.left == old_node then
		up.left = new_node
	else
		up.right = new_node
	end
end

function set_i:insert(to_insert)
	local mt = getmetatable(to_insert)
	assert(mt and mt.jnet_base__ == net.net_m, "argument #1 is not a net")
	if not self.all_ then
		self.all_ = to_insert.all_
	end
	assert(self.all_ == to_insert.all_, "argument #1 is of the wrong bit count")
	local prev = self.root_
	local prevbit = false
	local curr = self.root_.left
	for i = to_insert.all_ - 1, to_insert.all_ - to_insert.netwb_ - 1, -1 do
		if not curr then
			curr = {
				up = prev,
			}
			prev[prevbit and "right" or "left"] = curr
		end
		if curr.net then
			return false
		end
		if i == to_insert.all_ - to_insert.netwb_ - 1 then
			break
		end
		local bit = to_insert:bit(i)
		prev = curr
		prevbit = bit
		curr = curr[bit and "right" or "left"]
	end
	replace(curr, {
		up = curr.up,
		net = to_insert,
	})
	while true do
		if prev.left and prev.left.net and prev.right and prev.right.net then
			replace(prev, {
				up = prev.up,
				net = prev.left.net ^ -1,
			})
			prev = prev.up
		else
			break
		end
	end
	return true
end

function set_i:remove(to_remove)
	local mt = getmetatable(to_remove)
	assert(mt and mt.jnet_base__ == net.net_m, "argument #1 is not a net")
	if not self.all_ then
		return false
	end
	assert(self.all_ == to_remove.all_, "argument #1 is of the wrong bit count")
	local prev = self.root_
	local prevbit = false
	local curr = self.root_.left
	local fragmented
	for i = to_remove.all_ - 1, to_remove.all_ - to_remove.netwb_ - 1, -1 do
		if not curr then
			return false
		end
		if curr.net and curr.net:contains(to_remove) then
			fragmented = curr.net
			break
		end
		if i == to_remove.all_ - to_remove.netwb_ - 1 then
			break
		end
		local bit = to_remove:bit(i)
		prev = curr
		prevbit = bit
		curr = curr[bit and "right" or "left"]
	end
	replace(curr, nil)
	while true do
		if prev.up and not prev.left and not prev.right then
			replace(prev, nil)
			prev = prev.up
		else
			break
		end
	end
	if fragmented then
		for i = to_remove.netwb_ - 1, fragmented.netwb_, -1 do
			local flip = to_remove:flip()
			self:insert(flip)
			if to_remove > flip then
				to_remove = flip
			end
			to_remove = to_remove ^ -1
		end
	end
	return true
end

function set_i:contains(to_find)
	local mt = getmetatable(to_find)
	assert(mt and mt.jnet_base__ == net.net_m, "argument #1 is not a net")
	if not self.all_ then
		return false
	end
	assert(self.all_ == to_find.all_, "argument #1 is of the wrong bit count")
	local prev = self.root_
	local prevbit = false
	local curr = self.root_.left
	for i = to_find.all_ - 1, to_find.all_ - to_find.netwb_ - 1, -1 do
		if not curr then
			return false
		end
		if curr.net and curr.net:contains(to_find) then
			return curr.net
		end
		if i == to_find.all_ - to_find.netwb_ - 1 then
			break
		end
		local bit = to_find:bit(i)
		prev = curr
		prevbit = bit
		curr = curr[bit and "right" or "left"]
	end
	return false
end

function set_i:nets()
	return coroutine.wrap(function()
		local prev = self.root_
		local curr = self.root_.left or self.root_
		while true do
			if curr == self.root_ then
				return
			end
			if curr.net then
				coroutine.yield(curr.net)
			end
			local pprev = prev
			prev = curr
			if pprev == curr.up then
				curr = curr.left or curr.right or curr.up
			elseif pprev == curr.left then
				curr = curr.right or curr.up
			elseif pprev == curr.right then
				curr = curr.up
			end
		end
	end)
end

function set_i:add(other)
	assert(getmetatable(other) == getmetatable(self), "other operand is of the wrong type")
	if not other.all_ then
		return
	end
	assert(not self.all_ or self.all_ == other.all_, "other operand is of the wrong bit count")
	for net in other:nets() do
		self:insert(net)
	end
end

function set_i:subtract(other)
	assert(getmetatable(other) == getmetatable(self), "other operand is of the wrong type")
	if not other.all_ then
		return
	end
	assert(not self.all_ or self.all_ == other.all_, "other operand is of the wrong bit count")
	for net in other:nets() do
		self:remove(net)
	end
end

function set_i:intersect(other)
	assert(getmetatable(other) == getmetatable(self), "other operand is of the wrong type")
	local self_minus_other = self - other
	local other_minus_self = other - self
	self:add(other)
	self:subtract(self_minus_other)
	self:subtract(other_minus_self)
end

function set_m:__add(other)
	local clone = self:clone()
	clone:add(other)
	return clone
end

function set_m:__sub(other)
	local clone = self:clone()
	clone:subtract(other)
	return clone
end

function set_m:__mul(other)
	local clone = self:clone()
	clone:intersect(other)
	return clone
end

local function new()
	return setmetatable({
		root_ = {},
		all_ = false,
	}, set_m)
end

function set_i:clone()
	local clone = new()
	for net in self:nets() do
		clone:insert(net)
	end
	return clone
end

local function range(first, last)
	local mt = getmetatable(first)
	assert(mt and mt.jnet_base__ == net.net_m, "argument #1 is not a net")
	assert(getmetatable(last) == getmetatable(first), "argument #2 is of the wrong type")
	assert(first.all_ == last.all_, "argument #2 is of the wrong bit count")
	assert(first.netwb_ == last.netwb_, "argument #2 is of the wrong network bit count")
	local all = new()
	all:insert(first:promote_(0, 0))
	for i = 1, first.netwb_ do
		local flip = first:flip()
		if first > flip then
			first = flip
			all:remove(flip)
		end
		first = first ^ -1
	end
	for i = 1, last.netwb_ do
		local flip = last:flip()
		if last > flip then
			last = flip
		else
			all:remove(flip)
		end
		last = last ^ -1
	end
	return all
end

return {
	new = new,
	range = range,
	set_m = set_m,
}
