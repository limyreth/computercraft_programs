-- Titan, orders all Drones

-- REQUIRES: is at least a computer, with modem on top
-- ENSURE: At any point in time, handle server crashes well

catch(function()

Titan = Object:new()
Titan._STATE_FILE = "/titan.state"

function Titan:new()
	local obj = Object.new(self)
	obj:_load()
	return obj
end

function Titan:_load()
	-- load transient
	self._home_pos = gps_.persistent_locate()
	self._home_chunk = vector.new(
		math.floor(self._home_pos.x / CHUNK_SIZE),
		math.floor(self._home_pos.y / CHUNK_SIZE),
		math.floor(self._home_pos.z / CHUNK_SIZE)
	)
	self._home_pos.x = math.floor((self._home_chunk.x + 0.5) * CHUNK_SIZE)
	self._home_pos.z = math.floor((self._home_chunk.z + 0.5) * CHUNK_SIZE)
	
	self._mining_system = MiningSystem:new(self._home_pos)
	self._build_system = BuildSystem:new(self._home_chunk, self._mining_system)
	self._garbage_system = GarbageSystem:new(self._home_pos, self._mining_system)
	
	-- load persistent things
	local state = io.from_file(self._STATE_FILE)
	if state then
		table.merge(self, state)
	else
		self._drones = {}
		self:_save()
	end
end

function Titan:_save()
	io.to_file(self._STATE_FILE, {
		_drones = self._drones,
	})
	self._build_system:save()
	self._mining_system:save()
	self._garbage_system:save()
end

function Titan:_send(destination, contents)
	local msg = {user='limyreth'}
	msg.contents = contents
	msg = textutils.serialize(msg)
	rednet.send(destination, msg);
end

-- Returns position nearest to given pos where there is guaranteed free space (i.e. mined out and has no chunks built there)
function Titan:_get_nearest_free_pos(pos)
	local chunk = vector.copy(pos)
	chunk.x = math.floor(chunk.x / CHUNK_SIZE)
	chunk.z = math.floor(chunk.z / CHUNK_SIZE)
	
	local free_pos = vector.copy(pos)
	if chunk.x == self._home_chunk.x and chunk.z == self._home_chunk.z then
		-- seeing how the mining sys works, this spot is most likely to be mined out, outside the home chunk
		free_pos.x = (self._home_chunk.x+1) * CHUNK_SIZE
		free_pos.z = (self._home_chunk.z+1) * CHUNK_SIZE - 1
	else	
		local dc = self._home_chunk - chunk
		if chunk.x % 2 == self._home_chunk.x % 2 then
			-- we're not in empty chunk x-wise
			if dc.x > 0 then
				chunk.x = chunk.x + 1
			else
				chunk.x = chunk.x - 1
			end
		end
		
		if chunk.z % 2 == self._home_chunk.z % 2 then
			-- we're not in empty chunk z-wise
			if dc.z > 0 then
				chunk.z = chunk.z + 1
			else
				chunk.z = chunk.z - 1
			end
		end
		
		free_pos.x = chunk.x * CHUNK_SIZE
		free_pos.z = chunk.z * CHUNK_SIZE
	end
	
	if self._mining_system:is_pos_mined(free_pos) then
		return free_pos
	else
		log('no nearest free pos')
		log(free_pos)
		return pos
	end
end

function Titan:run()
	rednet.open('top')
	while true do
		local sender, msg, distance = rednet.receive()
		msg = textutils.unserialize(msg)
		if msg.user == 'limyreth' then
			self._mining_system:finished_mining(sender)
			if msg.contents.type == 'nearest_free_pos_request' then
				self:_send(sender, self:_get_nearest_free_pos(msg.contents.drone_pos))
			elseif msg.contents.type == 'command_request' then
			
				if self._drones[sender] == nil then
					self._drones[sender] = {state=DroneState.INITIAL}
				end
				
				local stats = msg.contents.drone_stats
				local drone = self._drones[sender]
				
				-- switch drone state if it actually finished its last command
				if drone.state == DroneState.INITIAL or stats.finished then
					if drone.state == DroneState.INITIAL or drone.state == DroneState.MINING or drone.state == DroneState.DROP_ALL then
						if stats.can_mine then
							drone.state = DroneState.MINING
							drone.target_pos = self._mining_system:get_next(sender)
						else
							drone.state = DroneState.DROP_JUNK
							drone.target_pos = self._garbage_system:get_next()
						end
					elseif drone.state == DroneState.DROP_JUNK or drone.state == DroneState.BUILDING then
						drone.state = DroneState.DROP_ALL
						
						if stats.can_build then
							local succeeded, build_pos = try(self._build_system.get_next, self._build_system)
							if succeeded then
								assert(build_pos)
								drone.state = DroneState.BUILDING
								drone.target_pos = build_pos
							else
								local err_str = build_pos
								local _, err = exceptions.deserialize(err_str)
								if err.type ~= 'NoRoomException' then
									error(err_str)
								end
							end
						end
					else
						assert(false)
					end
					
					self:_save()
				end
				
				-- send command
				self:_send(sender, drone)
				
			else
				assert(false)
			end
		end
	end
end

end)