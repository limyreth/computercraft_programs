-- Mine layers [6, 15] (<6 has bedrock)
-- Makes a shaft down from its starting/home location, mines in circular, counter-clockwise fashion
-- Returns when full
-- Starting location is passed as program args and is referred to as Home location
-- Startup script calls this thing!
-- Drops stuff in chest top of home location

-- ENSURE: At any point in time, program must be able to handle being aborted and restarted

-- TODO mining higher when layer finished. Might even provide height to dig at as an arg...

catch(function()

Miner = Object:new()
Miner._STATE_FILE = "/miner.state"
Miner._engines = turtle.engines

function Miner:new()
	local obj = Object.new(self)
	obj:_load()
	return obj
end

-- Load from file
function Miner:_load()
	self._driver = Driver:new()
	self._max_radius = 60
	self._max_height = 30
	
	-- load persistent things
	local state = io.from_file(self._STATE_FILE)
	if state then
		table.merge(self, state)
	else
		self._home_pos = gps_.persistent_locate()
		
		-- where we currently/will mine
		self._mining_pos = vector.copy(self._home_pos)
		self._mining_pos.y = 7
		
		self:_save()
	end
end

-- Save state to file
function Miner:_save()
	io.to_file(self._STATE_FILE, {
		_home_pos = self._home_pos,
		_mining_pos = self._mining_pos,
	})
end

function Miner:_go_home()
	self._driver:go_to(self._home_pos, {'x', 'z', 'y'})
end

function Miner:_go_to_mine()
	if self._mining_pos.y > self._max_height then
		error({type="FinishedMiningException", message="Finished mining this patch"})
	end
	
	if self:_is_low_on_fuel() then
		Exception("Low on fuel")
	end
	
	self._driver:go_to(self._mining_pos, {'y', 'x', 'z'})
end

function Miner:_set_next_mining_pos()
	-- make a drawing if you don't understand the math
	local dp = self._mining_pos:sub(self._home_pos)
	local d = math.max(math.abs(dp.x), math.abs(dp.z))
	
	-- Note: the ordering of the ifs is reverse chronological, which is crucial for correct behaviour
	if (dp.x == d and dp.z == d) then
		-- finished a square (!= tile), move to next square
		self._mining_pos.x = self._mining_pos.x + 1
		if d == self._max_radius then
			local height = self._mining_pos.y
			self._mining_pos = vector.copy(self._home_pos)
			self._mining_pos.y = height + 3
		end
		-- Note: d += 1
	elseif dp.z == d then
		-- go up (when viewing the XZ plane frontally with X pointing up, Z pointing right)
		self._mining_pos.x = self._mining_pos.x + 1
	elseif dp.x == -d then
		-- go right
		self._mining_pos.z = self._mining_pos.z + 1
	elseif dp.z == -d then
		-- go down 
		self._mining_pos.x = self._mining_pos.x - 1
	elseif dp.x == d then
		-- go left
		self._mining_pos.z = self._mining_pos.z - 1
	end
end

function Miner:_mine()
	if table.equals(self._driver:get_pos(), self._home_pos) then
		self:_empty_inventory()
	end
	
	self:_go_to_mine()
	
	while true do
		-- Drill in all directions
		for direction, engine in pairs(self._engines) do
			if engine:detect() then
				engine:dig()
				if turtle.getItemCount(16) > 0 then
					-- we might drop items if we dig more
					Exception("Inventory full")
				end
			end
		end
		
		-- Move to next tile
		self:_set_next_mining_pos()
		self:_save()
		self:_go_to_mine()
	end
end

function Miner:_is_low_on_fuel()
	local needed_fuel = (math.abs(self._mining_pos.x - self._home_pos.x) +
							math.abs(self._mining_pos.y - self._home_pos.y) +
							math.abs(self._mining_pos.z - self._home_pos.z) +
							10)  -- margin of 10
	return needed_fuel > turtle.getFuelLevel()
end

function Miner:_empty_inventory()
	print("Emptying inventory")
	while not turtle.is_inventory_empty() do
		self._engines[Direction.UP]:drop_all()
		sleep(5)
	end
	turtle.select(1)
end

-- main miner loop
function Miner:run()
	while true do
		if turtle.getFuelLevel() < 200 then
			_, err = xpcall(function() Exception("Low on fuel") end, print_exception)
			self:_go_home()
			error(err)
		end
		
		term.clear()
		term.setCursorPos(1, 1)
		
		-- mine
		_, err = xpcall(function() self:_mine() end, print_exception)
		self:_go_home()
		
		if err.type == 'FinishedMiningException' then
			error(err)
		end
		
		if turtle.is_inventory_empty() then
			Exception("Did not mine anything, something's wrong")
		end
		self:_empty_inventory()
	end
end

end)