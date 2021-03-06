-- Exception handling

local _error = error
function error(table_, level)
	level = level or 1
	if level == 0 then
		level = 1  -- force level > 0, as our exception handler expects this
	end
	_error(textutils.serialize(table_), level+1)
end

function print_exception(error_string)
	return log_exception(error_string, true)
end

-- print and abort
local function handle_exception(error_string)
	print_exception(error_string)
	_error()  -- abort
end

-- exactly like pcall, but doesn't display thrown error
function try(...)
	local f = table.remove(arg, 1)
	return xpcall(function() return f(unpack(arg)) end, log_exception)  -- note: xpcall annoyingly does a tostring on whatever the error handler returns
end

-- catches exceptions, prints them properly, then crashes the application
-- func: a function with no args that returns nothing
function catch(func)
	xpcall(func, handle_exception)
end

-- basic Exception
function Exception(message)
	error({type="Exception", message=message}, 2)
end

exceptions = {}
function exceptions.deserialize(str)
	require_(str ~= nil)
	local prefix, e = string.match(str, "([^:]+:[^:]+: )(.+)")
	e = textutils.unserialize(e)
	if type(e) ~= 'table' then
		e = {type='', message=e}
	end
	return prefix, e
end
