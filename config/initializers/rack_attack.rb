Rack::Attack.throttle("logins/ip", limit: 5, period: 20) do |req|
  req.ip if req.path == "/session" && req.post?
end

Rack::Attack.throttle("logins/email", limit: 5, period: 20) do |req|
  req.params["email"].to_s.downcase.presence if req.path == "/session" && req.post?
end
