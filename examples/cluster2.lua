local skynet = require "skynet"
local cluster = require "skynet.cluster"

local db_addr = nil
local proxy = nil
local largekey = string.rep("K", 1024)
local largevalue = string.rep("V", 100 * 1024)

local function test1()
	print("test1: set largekey by proxy")
	skynet.call(proxy, "lua", "SET", largekey, largevalue)

	print("test1: get largekey by proxy")
	local v1 = skynet.call(proxy, "lua", "GET", largekey)
	print("test1 proxy: largeValuelen=" .. #v1)

	-- 这里会报错, 因为这个地址是对于db节点的, 所以不能直接调用, 跨节点，必须通过proxy调用
	print("test1: get largekey by db_addr")
	local v2 = skynet.call(db_addr, "lua", "GET", largekey)
	print("test1 db_addr: largeValuelen=" .. #v2)
end

local function test2()
	print("ping proxy")
	skynet.send(proxy, "lua", "PING", "proxy")

	skynet.fork(function()
		skynet.trace("cluster")
		print("fork get a&b")
		print(cluster.call("db", "@sdb", "GET", "a"))

		print(cluster.call("db2", "@sdb", "GET", "b"))

		print("ping db2 with longstring:")
		cluster.send("db2", "@sdb", "PING", "db2:longstring" .. largevalue)
	end)

	-- test snax service
	skynet.timeout(300, function()
		print("reload cluster config with db3, and db is down")
		cluster.reload {
			db = false, -- db is down
			db3 = "127.0.0.1:2529"
		}
		print(pcall(cluster.call, "db", "@sdb", "GET", "a")) -- db is down
	end)

	print("reload cluster config with nowaiting false")
	cluster.reload { __nowaiting = false }
	local pingserver = cluster.snax("db3", "pingserver")
	print("ping db3 with hello:")
	print(pingserver.req.ping "hello")
end

skynet.start(function()
	-- 这里不能要@, 是因为 clusteragent.dispatch_request 逻辑: 在addr==0时 register_name["@" .. name]
	db_addr = cluster.query("db", "sdb")
	print("service sdb addr: " .. db_addr)

	-- 这里需要@, 是因为 clusteragent.register_name_mt 逻辑: local addr = skynet.call(clusterd, "lua", "queryname", name:sub(2))	-- name must be '@xxxx'
	proxy = cluster.proxy "db@sdb" -- cluster.proxy("db", "@sdb")
	print("proxy sdb addr: " .. proxy)

	test1()
end)
