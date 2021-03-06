-- Manages where drones may drop junk
-- assigns valid positions in a round robin system

-- ENSURE: At any point in time, program must be able to handle being aborted and restarted

catch(function()

GarbageSystem = Object:new()
GarbageSystem._STATE_FILE = "/garbage_system.state"
GarbageSystem._DROP_HEIGHT = 80 - 16
GarbageSystem._RADIUS = 7  -- musn't be a multiple of 3
GarbageSystem._LOCATION_COUNT = GarbageSystem._RADIUS * GarbageSystem._RADIUS  -- number of garbage locations to provide

function GarbageSystem:new(home_pos, mining_system)
	local obj = Object.new(self)
	self._home_pos = vector.copy(home_pos)
	obj._mining_system = mining_system
	obj:_load()
	return obj
end

function GarbageSystem:_load()
	local state = io.from_file(self._STATE_FILE)
	if state then
		table.merge(self, state)
	else
		self._last_location = 0
	end
end

function GarbageSystem:save()
	io.to_file(self._STATE_FILE, {
		_last_location = self._last_location,
	})
end

-- returns next available pos and considers it assigned to whoever requested it
function GarbageSystem:get_next()
	local pos
	repeat
		self._last_location = (self._last_location + 3) % self._LOCATION_COUNT
		
		pos = vector.copy(self._home_pos)
		pos.x = pos.x + math.floor((self._last_location - self._LOCATION_COUNT / 2) / self._RADIUS)
		pos.y = GarbageSystem._DROP_HEIGHT
		pos.z = pos.z + (self._last_location % self._RADIUS) - math.floor(self._RADIUS/2)
	until self._mining_system:is_pos_mined(pos)
	return pos
end

end)