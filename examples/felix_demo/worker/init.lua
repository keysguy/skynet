local skynet = require "skynet"
local skynet_manager = require "skynet.manager"
local worker = require "service"

worker.money = 0
worker.isworking = false

function worker:update(frame)
    if self.isworking then
        self.money = self.money + 1
        skynet.error(self.name .. tostring(self.id) .. ", money: " .. tostring(self.money))
    end
end

worker.init = function()
    local selfAddr = skynet.self()
    skynet.error(worker.name .. " - " .. worker.id .. " - " .. selfAddr .. " inited")
    skynet.name("felix_worker", skynet.self())
    --skynet.register("felix_worker")
    skynet.fork(worker.timer, worker)
end

function worker:timer()
    skynet.error(self.name .. " " .. self.id .. " timer start")
    local stime = skynet.now()
    local frame = 0
    while true do
        frame = frame + 1
        local isok, err = pcall(self.update, self, frame)
        if not isok then
            skynet.error(err)
        end
        local etime = skynet.now()
        local waittime = frame * 20 - (etime - stime)
        if waittime <= 0 then
            waittime = 2
        end
        skynet.sleep(waittime)
    end
end


worker.resp.start_work = function(source)
    worker.isworking = true
end

worker.resp.stop_work = function(source)
    worker.isworking = false
end

worker.resp.change_money = function(source, delta)
    worker.money = worker.money + delta
    skynet.error(worker.name .. " " .. worker.id .. " change money to: " .. tostring(worker.money))
    return worker.money
end

worker.start(...)
